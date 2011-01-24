#!/bin/sh

bin/mkbootfs root | gzip > ramdisk.img

if [ $? -ne 0 ]; then 
	exit
fi

$ANDROID_BUILD_TOP/prebuilt/linux-x86/toolchain/arm-eabi-4.4.0/bin/arm-eabi-mkimage \
-A arm -O linux -T ramdisk -C none -a 0x90308000 \
-n "Android Root Filesystem" \
-d ramdisk.img uramdisk.img && rm ramdisk.img

