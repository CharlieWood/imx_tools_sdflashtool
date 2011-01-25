#!/bin/sh
#
# Flash sd Card layout
# /images
#   |----[repartition]
#   |----[clearubootenv]
#   |----[partition.cfg]
#   |
#   |----md5sum.txt
#   |
#   |----[u-boot-no-padding.bin]
#   |----[uImage]
#   |----[uramdisk.img]
#   |----[uImage-recovery]
#   |----[uramdisk-recovery.img]
#   |----[system.img]
#   |----[userdata.img]
#

# flash sd card define
mem_logfile="/tmp/flash.log"
img_path="/src/update/images"

# see also mkdevs.sh
src_dev="/dev/sd1"
target_dev="/dev/emmc"

# partition
#           1       2          (3) 5           6        7               4
# [  boot  ][  sd  ][  system  ][  [ data ][ cache ][ wowconfig ]  ][  recovery  ]
#
# boot
# 0    1k      1M      4M            5M               8M
# [MBR][u-boot][uImage][uramdisk.img][uImage-recovery][uramdisk-recovery.img]
#
#Physics Division
#           2          (3) 7            6        5          4             1
# [  boot  ][  system  ][  [ wowconfig ][ cache ][ data ]  ][  recovery  ][ sd ]


# override by SDCard/images/partition.cfg
# unit: M
boot_space=32
system_space=256
data_space=1024
cache_space=512
recovery_space=16
wowconfig_space=16

export PATH=/bin:/sbin:/usr/bin

# do_log message
do_log()
{
	if [ $# -ne 0 ]; then
		echo "`date '+%F %T'`: $*" >> "$logfile"
	fi
}

# log_run cmd [args...]
log_run()
{
	do_log "Running: $@"
	$@ > /tmp/run.log 2>&1
	rc=$?
	cat /tmp/run.log >> "$logfile"
	do_log "return code is: $rc"
	return $rc
}

# show_message [-n] message
show_message()
{
	if [ "$#" -ne 0 -a "$1" = "-n" ]; then
		shift
		if [ "$#" -ne 0 ]; then
			ui_client -n "$1"
			echo -n "$1"
		fi
	else
		ui_client "$1"
		echo "$1"
	fi
	do_log "$1"
}

# get_target_size <no_arg>, unit: G
get_device_geometry()
{
	dev_cyls=`fdisk -l ${target_dev} | grep "heads" | grep "sectors" | grep "cylinders" | sed -e "s/[^0-9 ]//g"|tr -s ' '|cut -f 3 -d' '`
	dev_unitsize=`fdisk -l ${target_dev} | grep "^Units = " | sed -e "s/[^0-9 ]//g;s/.* \([0-9]\+\) *$/\1/g"`

	if [ -z "$dev_cyls" -o -z "$dev_unitsize" -o "$dev_cyls" -le 0 -o "$dev_unitsize" -le 0 ]; then
		return 1
	fi
	return 0
}

# mkfs <partition_id> <cmd> <desc>
mkfs()
{
	show_message -n "make filesystem for $3, please wait ... "
	log_run "$2" ${target_dev}$1
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"
	return 0
}

# check_img_space_var <img_name> <var_name>
check_img_space_var()
{
	# check image size
	if [ -f "$img_path/$1" ]; then
		img_size=$(((`stat -c %s "$img_path/$1"` + 1048575) / 1048576))

		eval "var_space=\$$2"
		if [ "$var_space" -lt "$img_size" ]; then
			do_log "WARNING: enlarge image space $2 for "$1" = $img_size"
			eval "\$$2=$img_size"
		fi
	fi
}

# doapartition <no_args>_
do_partition()
{
	# read userdefined partition size
	if [ -f "$img_path/partition.cfg" ]; then
		. "$img_path/partition.cfg"
	fi

	# check xxx_space variable
	if [ -z "$boot_space" -o -z "$system_space" -o \
			-z "$data_space" -o -z "$cache_space" -o -z "$recovery_space" ]; then
		show_message "space variable not setup"
		return 1
	fi

	# check system_space size
	check_img_space_var "system.img" "system_space"

	# clear MBR
	show_message -n "clear old partition table ... "
	dd if=/dev/zero of="$target_dev" bs=1 seek=446 count=64 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"

	# get target device geometry
	show_message -n "get target device geometry ... "
	get_device_geometry
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"

	boot_size=$((boot_space * 1024 * 1024 / dev_unitsize))
	system_size=$((system_space * 1024 * 1024 / dev_unitsize))
	wowconfig_size=$((wowconfig_space * 1024 * 1024 / dev_unitsize))
	recovery_size=$((recovery_space * 1024 * 1024 / dev_unitsize))
	cache_size=$((cache_space * 1024 * 1024 / dev_unitsize))
	data_size=$((data_space * 1024 * 1024 / dev_unitsize))
	sd_size=$((dev_cyls - boot_size - system_size - data_size - cache_size - recovery_size - wowconfig_size))

	boot_end=$((boot_size - 1))
	system_end=$((boot_end + system_size))
	ext_end=$((system_end + wowconfig_size + data_size + cache_size))
	wowconfig_end=$((system_end + wowconfig_size))
	cache_end=$((wowconfig_end + cache_size))
	data_end=$((cache_end + data_size)) 
	recovery_end=$((ext_end + recovery_size))

	part_cmds="n p 2 $boot_end $system_end
			n p 4 $((ext_end+1)) $recovery_end
			n p 1 $((recovery_end+1)) AUTO
			n e $((system_end+1)) $ext_end
			n $((cache_end+1)) $data_end
			n $((wowconfig_end+1)) $cache_end
			n AUTO AUTO
			t 1 b
			w"

	show_message "create new partition table ... "
	for i in $part_cmds; do
		if [ "$i" = "AUTO" ]
		then
			echo ""
		else
			echo "$i"
		fi
	done | log_run fdisk "$target_dev"

	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"

	#mkfs 1 "mkfs.vfat -n 'sd'" "user card space" &&
	#mkfs 2 "mkfs.ext4 -j -O ^extent -L 'system'" "system" && 
	#mkfs 4 "mkfs.ext4 -j -O ^extent -L 'userdata'" "data" &&
	#mkfs 7 "mkfs.ext4 -j -O ^extent -L 'wowconfig'" "wowconfig" && 
	#mkfs 5 "mkfs.ext4 -j -O ^extent -L 'recovery'" "recovery"  &&
	#mkfs 6 "mkfs.ext4 -j -O ^extent -L 'cache'" "cache" || return 1
	mkfs 1 "mkfs.vfat -n 'sd'" "user card space" &&
	mkfs 5 "mke2fs -j -O ^extent -L 'userdata'" "data" &&
	mkfs 6 "mke2fs -j -O ^extent -L 'cache'" "cache" &&
	mkfs 7 "mke2fs -j -O ^extent -L 'wowconfig'" "wowconfig" || return 1 

	return 0
}

# get partition size (unit: bytes)
# get_partitions <no_args>
get_partitions()
{
	log_run fdisk -u -l "${target_dev}"
	for part in `fdisk -u -l "${target_dev}" | grep "^${target_dev}" | tr -d '*' | \
			tr -s ' ' | sed -e "s?^${target_dev}[^0-9]*??" | tr ' ' '|'`; do
		dev=`echo "$part"|cut -f 1 -d'|'`
		begin=`echo "$part"|cut -f 2 -d '|'`
		end=`echo "$part"|cut -f 3 -d '|'`
		size=$(((end - begin) * 512))
		eval "partsize_${dev}=$size"
	done
}

# check_space_size <img_name> <part_no>
check_space_size()
{
	if [ -f "$img_path/$1" ]; then
		imgsize=`stat -c %s "$img_path/$1"`
		eval "partsize=\$partsize_$2"
		if [ "$partsize" -lt "$imgsize" ]; then
			show_message "FAIL"
			show_message "image '$1' large that partition space, can't flash to target device"
			return 1
		fi
	fi
	return 0
}

# check_img_size <img_name> <size unit: k>
check_img_size()
{
	if [ -f "$img_path/$1" ]; then
		img_size=$(((`stat -c %s "$img_path/$1"` + 1023) / 1024))

		if [ "$2" -lt "$img_size" ]; then
			show_message "FAIL"
			show_message "image '%1' too large, can't flash"
			return 1
		fi
	fi

	return 0
}

# check_partition <no_args>
check_partition()
{
	# get all partitions size
	show_message -n "get partition list ... "
	get_partitions
	if [ -z "$partsize_2" -o -z "$partsize_4" -o -z "$partsize_5" -o -z "$partsize_6" ]; then
		show_message "FAIL"
		show_message "no enough partition"
		show_message "'repartition' option is need by flash to a new device."
		return 1
	fi
	show_message "OK"

	show_message -n "check image size ... "
	check_img_size "u-boot-no-padding.bin" 1023 &&
	check_img_size "uImage" 3072 &&
	check_img_size "uramdisk.img" 1024 &&
	check_img_size "uImage-recovery" 3072 &&
	check_img_size "uramdisk-recovery.img" 8192 &&
	check_space_size "system.img" 2 || return 1
	show_message "OK"

	return 0
}

# flash_image <img_name> <title> <flash_mode> <part/offset> [label]
flash_image()
{
	img="$img_path/$1"
	title="$2"
	mode="$3"
	offset="$4"
	label="$5"

	if [ ! -f "$img" ]; then
		return 0
	fi

	show_message -n "flash image: $title please wait ... "

	if [ "$mode" = "cp" ]; then
		cmd1="mke2fs -j -O ^extent -L '$label' ${target_dev}${offset}"
		cmd2="mount -o loop,ro "$img" /img"
		cmd3="mount "${target_dev}${offset}" /img2"
		cmd4="cp -a /img/* /img2"
		cmd5="umount /img2"
		cmd6="umount /img"

		desc1="make filesystem for '${target_dev}${offst}' failed"
		desc2="mount img to /img failed"
		desc3="mount target to /img2 failed"
		desc4="copy files from /img to /img2 failed"
		desc5="can't umount /img2"
		desc6="can't umount /img"

		for i in 1 2 3 4 5 6; do
			eval "cmd=\$cmd${i}"
			log_run $cmd
			if [ $? -ne 0 ]; then
				show_message "FAIL"
				eval "desc=\$desc${i}"
				show_message "$desc"
				return 1
			fi
		done

		losetup -d /dev/loop0 2> /dev/null

		show_message "OK"
		return 0
	fi

	case "$mode" in
		"dd_part")
			log_run dd if="$img" of="$target_dev$offset" bs=4096
			;;
		"dd_offset")
			log_run dd if="$img" of="$target_dev" bs=1024 seek="$offset"
			;;
		*)
			show_message "FAIL"
			show_message "flash program error, unknown flash mode"
			return 1
			;;
	esac

	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi

	show_message "OK"
	return 0
}

# wait_device <control number> <dev_name>
wait_device()
{
	show_message -n "wait device on eMMC control $1 to ready ."
	for i in 1 2 3 4 5 6 7 8 9 10; do
		if [ ! -d /sys/devices/platform/mxsdhci.$1/mmc_host/mmc$1/mmc${1}*/block/mmcblk* ]; then
			sleep 1
			continue
		fi

		major=`cat /sys/devices/platform/mxsdhci.$1/mmc_host/mmc$1/mmc${1}*/block/mmcblk*/dev | cut -f 1 -d ':'`
		minor=`cat /sys/devices/platform/mxsdhci.$1/mmc_host/mmc$1/mmc${1}*/block/mmcblk*/dev | cut -f 2 -d ':'`
		show_message "OK"

		show_message -n "create device files: "
		mknod /dev/$2 b $major $minor
		for j in 1 2 3 4 5 6 7; do
			mknod /dev/$2$j b $major $((minor + j))
		done
		show_message "OK"
		return 0
	done
	show_message "FAIL"
	return 1
}

# read_md5sum <no_arg>
read_md5sum()
{
	if [ ! -f "$img_path/md5sum.txt" ]; then
		show_message "FAIL"
		show_message "md5sum.txt not found"
		return 1
	fi

	exec 4<&0 0<"$img_path/md5sum.txt"
	while read sum file; do
		file=`basename "$file" | tr -- '-.' '__'`
		eval "${file}_sum=$sum"
	done
	exec 0<&4 4<&-
}

# check_image_md5 <img_name>
check_image_md5()
{
	if [ ! -f "$img_path/$1" ]; then
		return 0
	fi

	show_message -n "checking md5sum for image $1 ... "
	eval "sum=\$`echo "$1" | tr -- '-.' '__'`_sum"
	if [ -z "$sum" ]; then
		show_message "FAIL"
		show_message "no md5sum info found in md5sum.txt"
		return 1
	fi

	realsum=`md5sum "$img_path/$1" | cut -f 1 -d ' '`

	if [ "$realsum" != "$sum" ]; then
		show_message "FAIL"
		show_message "md5 check failed"
		return 1
	fi

	show_message "OK"
	return 0
}

# quit <exit_code>
quit()
{
	umount /src > /dev/null 2> /dev/null
	exit "$1"
}

# check_enter_shell
check_enter_shell()
{
	echo "Press any letter key will enter a shell"
	sleep 1
	stty -echo -icanon time 0 min 0
	read line
	stty sane
	test -n "$line"
}

# program start here
logfile="$mem_logfile"
echo > "$logfile"

# wait for SD and eMMC ready
if [ "`id -u`" != "0" ]; then
	show_message "ERROR: only root can run flash"
	exit 1
fi

show_message "INFO: SD flash start ..."
show_message "INFO: source device is ${src_dev}"
show_message "INFO: target device is ${target_dev}"
show_message " "

# wait SD card and eMMC ready
wait_device 0 "sd" && wait_device 2 "emmc"
if [ $? -ne 0 ]; then
	show_message "device not ready, flash abort"
	exit 1
fi

# wait a key enter normal shell
check_enter_shell
if [ $? -eq 0 ]; then
	show_message "**** welcome ****"
	exit 1
fi

# mount sd card to /src
show_message -n "mount SD card: mount ${src_dev} to /src ... "
umount /src 2> /dev/null
log_run mount "${src_dev}" /src
if [ $? -ne  0 ]; then
	show_message "FAIL"
	show_message "can't mount SD card, flash abort"
	exit 1
fi
show_message "OK"

# check images directory
show_message -n "checking image directory ... "
if [ ! -d "${img_path}" ]; then
	show_message "FAIL"
	show_message "No images directory found, flash abort."
	umount /src
	exit 1
fi
show_message "OK"

# switch logfile to sd card
mkdir /src/update/logs > /dev/null 2>&1
logfile="/src/update/logs/flash.log"
echo "=================== `date` =================" >> "$logfile"
cat "$mem_logfile" >> "$logfile"

if [ -f "$img_path/md5sum.txt" ]; then
	# read images md5sum info
	show_message -n "read md5sum info ... "
	read_md5sum
	if [ $? -ne 0 ]; then
		quit 1
	fi
	show_message "OK"
	
	# check images md5sum
	check_image_md5 "u-boot-no-padding.bin" &&
	check_image_md5 "uImage" &&
	check_image_md5 "uramdisk.img" &&
	check_image_md5 "uImage-recovery" &&
	check_image_md5 "uramdisk-recovery.img" &&
	check_image_md5 "system.img" &&
	check_image_md5 "userdata.img" || quit 1
else
	show_message "*** No md5sum.txt found, don't check image md5sum"
fi

# partition check
if [ -f "${img_path}/repartition" ]; then
	show_message "repartition file found, begin partition"
	do_partition || quit 1
else
	show_message "checking partition and images"
	check_partition || quit 1
fi

# clear u-boot env
if [ -f "${img_path}/clearubootenv" ]; then
	show_message -n "clear u-boot environment ... "
	dd if=/dev/zero of=/dev/emmc bs=1k seek=768 count=256
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		quit 1
	fi
	show_message "OK"
fi

# flash all images
flash_image "u-boot-no-padding.bin" "u-boot" "dd_offset" 1 &&
flash_image "uImage" "kernel" "dd_offset" 1024 &&
flash_image "uramdisk.img" "ramdisk" "dd_offset" 4096 &&
flash_image "uImage-recovery" "recovery kernel" "dd_offset" 5120 &&
flash_image "uramdisk-recovery.img" "recovery ramdisk" "dd_offset" 8192 &&
flash_image "system.img" "system" "dd_part" 2 &&
flash_image "userdata.img" "userdata" "cp" 5 'userdata' || quit 1

# sync target device
show_message -n "syncing target device ... "
log_run sync ${target_dev}
if [ $? -ne 0 ]; then
	show_message "FAIL"
	quit 1
fi
show_message "OK"

# umount /src
show_message -n "umount /src ... "
logfile="$mem_logfile"
log_run umount /src
if [ $? -ne 0 ]; then
	show_message "FAIL"
	exit 1
fi
show_message "OK"

show_message "flash success!"

return 0

