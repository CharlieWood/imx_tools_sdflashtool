#!/bin/sh

bin/mkbootfs root | gzip > ramdisk.img

if [ $? -ne 0 ]; then 
	exit
fi

bin/arm-none-linux-gnueabi-mkimage \
-A arm -O linux -T ramdisk -C none -a 0x90308000 \
-n "Android Root Filesystem" \
-d ramdisk.img uramdisk.img && rm ramdisk.img

