#!/bin/bash

flash_img="uImage uramdisk.img \
	uImage-recovery uramdisk-recovery.img system.img userdata.img"
uboot_img="u-boot-no-padding.bin"

images="$uboot_img $flash_img"

#usage <no_arg>
usage()
{
	echo "usage: `basename $0` -s src_directory -o out_dir -b board_name [-l] [-i]"
	echo "   -s: source directory"
	echo "   -o: output directory"
	echo "   -b: board name"
	echo "   -l: use ln instead of cp to copy image files"
	echo "   -i: create initialize release instead of update release"
	echo "       initialize release create new partition on target device"
	echo "          and clear u-boot environment"
	echo "       create a update release is default"
}

#err_exit <err_msg>
err_exit()
{
	echo "Error: $1"
	exit 1
}

usage_err()
{
	echo "Error: $1"
	usage
	exit 1
}

srcdir=""
outdir=""
boardname=""
CPCMD="cp"
rundir=`dirname "$0"`
initrel=0

while getopts 's:o:b:lih' OPT; do
	case $OPT in
		s)
			srcdir="$OPTARG"
			;;
		o)
			outdir="$OPTARG"
			;;
		b)
			boardname="$OPTARG"
			;;
		l)
			CPCMD="ln"
			;;
		i)
			initrel=1
			;;
		h|*)
			usage
			exit 1
			;;
	esac
done

test -z "$srcdir" && usage_err "no source directory"
test ! -d "$outdir" && usage_err "invalid output directory"
test -z "$boardname" && usage_err "no board name"

if [ ! -f "$srcdir/uramdisk-flash.img" ]; then
	err_exit "can't found flash uramdisk in source directory"
fi

echo "checking source images ..."
for i in $images; do
	test ! -f "$srcdir/$i" && err_exit "image $i not found in directory '$srcdir'"
done

dest="$outdir/update"
test -d "$dest" && err_exit "$dest directory exist, stop"

echo "src directory: $srcdir"
echo "output directory: $dest"
echo "board name: $boardname"
echo
echo "create output directory"
mkdir "$dest" &&
	mkdir "$dest/boot" &&
	mkdir "$dest/bin" &&
	mkdir "$dest/images" || err_exit "create directory failed"

echo "copy flash bin kernel and ramdisk"
/bin/cp "$srcdir/uImage" "$dest/bin" &&
	/bin/cp "$srcdir/uramdisk-flash.img" "$dest/bin/uramdisk.img" ||
		err_exit "copy file failed"

for i in $flash_img; do
	echo "copy file '$i' ..."
	$CPCMD "$srcdir/$i" "$dest/images/$i" || err_exit "copy file failed"
done

echo "copy u-boot images ..."
/bin/cp "$srcdir/$uboot_img" "$dest/boot/${boardname}_u-boot.img" || err_exit "copy u-boot failed"

if [ -f "$srcdir/md5sum.txt" ]; then
	echo "copy '$srcdir/md5sum.txt' to '$dest/images'"
	cp "$srcdir/md5sum.txt" "$dest/images/"
else
	for i in $images; do
		echo "md5sum for '$i' ... "
		sum=`md5sum $srcdir/$i | cut -f 1 -d ' '`
		echo "$sum $i" >> "$dest/images/md5sum.txt"
	done
fi

if [ "$initrel" = "1" ]; then
	echo "create initlaize flag files"
	touch "$dest/images/repartition"
	touch "$dest/images/clearubootenv"
fi

echo "Ok, release create success."

