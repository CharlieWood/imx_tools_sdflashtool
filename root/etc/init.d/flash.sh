#!/bin/sh
#
# Flash sd Card layout
# /images
#   |----[repartition]
#   |----[partition.cfg]
#   |
#   |----[uImage]
#   |----[uramdisk.img]
#   |----[system.img]
#   |----[userdata.img]
#   |----[uramdisk-recovery.img]
#

# flash sd card define
mem_logfile="/tmp/flash.log"
img_path="/src/update/images"

# see also mkdevs.sh
src_dev="/dev/sd1"
target_dev="/dev/emmc"

# partition
#           1       2          (3) 5       6           4
# [  boot  ][  sd  ][  system  ][  [ data ][ cache ]  ][  recovery  ]
#
# boot
# 0      1k            1M            4M
# [ MBR ][ u-boot ... ][ kernel ... ][ ramdisk ... ]
#

# override by SDCard/images/partition.cfg
# unit: M
boot_space=6
system_space=200
data_space=1024
cache_space=20
recovery_space=10

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
			echo -n "$1"
		fi
	else
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

# mkfs <partition_id> <label> <desc>
mkfs()
{
	show_message -n "make filesystem for $3 ... "
	log_run mke2fs -j ${target_dev}$1 -O ^extent -L "$2"
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"
	return 0
}

# doapartition <no_args>_
do_partition()
{
	# read userdefined partition size
	if [ -f "$img_path/partition.cfg" ]; then
		. "$img_path/partition.cfg"
	fi

	show_message -n "get target device geometry ... "
	get_device_geometry
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"

	# check xxx_space variable
	if [ -z "$boot_space" -o -z "$system_space" -o \
			-z "$data_space" -o -z "$cache_space" -o -z "$recovery_space" ]; then
		show_message "space variable not setup"
		return 1
	fi

	# check system_space size
	if [ -f "$img_path/system.img" ]; then
		system_img_size=$(((`stat -c %s "$img_path/system.img"` + 1048575) / 1048576))

		if [ "$system_space" -lt "$system_img_size" ]; then
			do_log "WARNING: enlarge system_space to system.img = $system_img_size"
			system_space=$system_img_size
		fi
	fi

	boot_size=$((boot_space * 1024 * 1024 / dev_unitsize))
	system_size=$((system_space * 1024 * 1024 / dev_unitsize))
	data_size=$((data_space * 1024 * 1024 / dev_unitsize))
	cache_size=$((cache_space * 1024 * 1024 / dev_unitsize))
	recovery_size=$((recovery_space * 1024 * 1024 / dev_unitsize))

	boot_end=$((boot_size - 1))
	sd_size=$((dev_cyls - boot_size - system_size - data_size - cache_size - recovery_size))
	sd_end=$((boot_end + sd_size))
	system_end=$((sd_end + system_size))
	ext_end=$((dev_cyls - recovery_size))
	data_end=$((system_end + data_size))

	# clear MBR
	show_message -n "clear old partition table ... "
	dd if=/dev/zero of="$target_dev" bs=1 seek=446 count=64 > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		show_message "FAIL"
		return 1
	fi
	show_message "OK"

	# create new partition table
	part_cmds="n p 1 $boot_end $sd_end
				n p 2 $((sd_end+1)) $system_end
				n e 3 $((system_end+1)) $ext_end
				n p $((ext_end+1)) AUTO
				n AUTO $data_end
				n AUTO AUTO
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

	mkfs 1 "sd" "user card space" &&
		mkfs 4 "recovery" "recovery" &&
		mkfs 5 "data" "userdata" &&
		mkfs 6 "cache" "cache" &&
	if [ $? -ne 0 ]; then
		return 1
	fi

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

# check_partition <no_args>
check_partition()
{
	# get all partitions size
	show_message -n "get partition liset ... "
	get_partitions
	if [ -z "$partsize_2" -o -z "$partsize_4" -o -z "$partsize_5" -o -z "$partsize_6" ]; then
		show_message "FAIL"
		show_message "no enough partition"
		return 1
	fi
	show_message "OK"

	show_message -n "check partition size ... "
	if [ -f "$img_path/system.img" ]; then
		size=`stat -c %s "$img_path/system.img"`
		if [ "$partsize_2" -lt "$size" ]; then
			show_message "FAIL"
			show_message "image system.img too large, can't flash to target device"
			return 1
		fi
	fi
	show_message "OK"

	return 0
}

# flash_image <img_name> <title> <flash_mode> <part/offset>
flash_image()
{
	if [ "$#" -ne 4 ]; then
		return 0
	fi

	img="$img_path/$1"
	title="$2"
	mode="$3"
	offset="$4"

	if [ ! -f "$img" ]; then
		return 0
	fi

	show_message -n "flash image: $title please wait ... "
	case "$mode" in
		"dd_part")
			log_run dd if="$img" of="$target_dev$offset" bs=4096
			;;
		"dd_offset")
			log_run dd if="$img" of="$target_dev" bs=1024 seek="$offset"
			;;
		"cp")
			cmd1="mount -o loop "$img" /img"
			cmd2="mount -o loop "${target_dev}${offset}" /img2"
			cmd3="cp -a /img/* /img2"
			cmd4="umount /img2"
			cmd5="umount /img"

			desc1="mount img to /img failed"
			desc2="mount target to /img2 failed"
			desc3="copy files from /img to /img2 failed"
			desc4="can't umount /img2"
			desc5="can't umount /img"

			for i in 1 2 3 4 5; do
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
			show_message -n "."
			sleep 1
			continue
		fi

		major=`cat /sys/devices/platform/mxsdhci.$1/mmc_host/mmc$1/mmc${1}*/block/mmcblk*/dev | cut -f 1 -d ':'`
		minor=`cat /sys/devices/platform/mxsdhci.$1/mmc_host/mmc$1/mmc${1}*/block/mmcblk*/dev | cut -f 2 -d ':'`
		show_message " OK"

		show_message -n "create device files: "
		show_message -n "$2"
		mknod /dev/$2 b $major $minor
		for j in 1 2 3 4 5 6 7; do
			show_message -n " ${2}${j}"
			mknod /dev/$2$j b $major $((minor + j))
		done
		show_message " OK"
		return 0
	done
	show_message " FAIL"
	return 1
}

# program start here
logfile="$mem_logfile"
echo > "$logfile"

# wait for SD and eMMC ready
if [ "`id -u`" != "0" ]
then
	show_message "only root can run flash"
	exit 1
fi

show_message "INFO: SD flash start ..."
show_message "INFO: source device is ${src_dev}"
show_message "INFO: target device is ${target_dev}"

# wait SD card and eMMC ready
wait_device 0 "sd" && wait_device 2 "emmc"
#wait_device "/dev/sd" "SD" && wait_device "/dev/emmc" "eMMC"
if [ $? -ne 0 ]; then
	show_message "device not ready, flash abort"
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
if [ ! -d "${img_path}" ]
then
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

# partition check
if [ -f "${img_path}/repartition" ]
then
	show_message "repartition file found, begin partition"
	do_partition
else
	show_message "checking partition and images"
	check_partition
fi

if [ $? -ne 0 ]; then
	umount /src
	exit 1
fi

flash_image "uImage" "kernel" "dd_offset" 1024 &&
	flash_image "uramdisk.img" "ramdisk" "dd_offset" 4096 &&
	flash_image "system.img" "system" "dd_part" 2 &&
	flash_image "userdata.img" "userdata" "cp" 5 &&
	flash_image "recovery.img" "recovery" "dd_part" 4
if [ $? -ne 0 ]; then
	umount /src
	exit 1
fi

show_message -n "syncing target device ... "
log_run sync ${target_dev}
if [ $? -ne 0 ]; then
	show_message "FAIL"
	umount /src
	exit 1
fi
show_message "OK"

show_message -n "umount /src ... "
logfile="$mem_logfile"
log_run umount /src
if [ $? -ne 0 ]; then
	show_message "FAIL"
	umount /src
	exit 1
fi
show_message "OK"

show_message "flash success!"

return 0
