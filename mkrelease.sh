#!/bin/bash

images="u-boot-no-padding.bin uImage uramdisk.img system.img userdata.img recovery.img"

#usage <no_arg>
usage()
{
	echo "usage: `basename $0` [-s src_directory] [-o out_dir] [-l] [-i]"
	echo "   -s: source directory, if omit, use environment variable ANDROID_PRODUCT_OUT"
	echo "   -o: output directory, if omit, use current work directory"
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

srcdir=""
outdir=""
CPCMD="cp"
rundir=`dirname "$0"`
initrel=0

if [ ! -f "$rundir/uramdisk.img" ]; then
	echo "can't found uramdisk.img in '$rundir'"
	echo "please run it from correct directory"
	exit 1
fi

while getopts 's:o:li' OPT; do
	case $OPT in
		s)
			srcdir="$OPTARG"
			;;
		o)
			outdir="$OPTARG"
			;;
		l)
			CPCMD="ln"
			;;
		i)
			initrel=1
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [ -z "$srcdir" ]; then
	srcdir="$ANDROID_PRODUCT_OUT"
fi

test -z "$srcdir" && err_exit "no source directory"

if [ -z "$outdir" ]; then
	outdir=`pwd`
fi

test ! -d "$outdir" && err_exit "invalid output directory"

for i in $images; do
	test ! -f "$srcdir/$i" && err_exit "image $i not found in directory '$srcdir'"
done

dest="$outdir/update"
test -d "$dest" && err_exit "$dest directory exist, stop"

echo "src directory: $srcdir"
echo "output directory: $dest"
echo
echo "create output directory"
mkdir "$dest" &&
	mkdir "$dest/bin" &&
	mkdir "$dest/images" &&
	mkdir "$dest/logs" || err_exit "create directory failed"

echo "copy flash bin kernel and ramdisk"
/bin/cp "$srcdir/uImage" "$dest/bin" &&
	/bin/cp "$rundir/uramdisk.img" "$dest/bin" || err_exit "copy file failed"

for i in $images; do
	echo "copy file '$i' ..."
	$CPCMD "$srcdir/$i" "$dest/images/$i" || err_exit "copy file failed"
done

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
	touch "$dest/images/repartition"
	touch "$dest/images/clearubootenv"
fi

echo "Ok, release create success."

