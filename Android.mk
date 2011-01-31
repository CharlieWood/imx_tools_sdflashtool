LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

flashramdisk: FLASH_RAMDISK_ROOT := $(LOCAL_PATH)
flashramdisk: $(PRODUCT_OUT)/uramdisk-flash.img

$(PRODUCT_OUT)/uramdisk-flash.img: | $(ACP)
	$(FLASH_RAMDISK_ROOT)/bin/mkbootfs $(FLASH_RAMDISK_ROOT)/root > \
		$(PRODUCT_OUT)/ramdisk-flash.img
	@echo "Install: $@"
	$(ANDROID_BUILD_TOP)/$(TARGET_TOOLS_PREFIX)mkimage \
		-A arm -O linux -T ramdisk -C none -a 0x90308000 \
		-n "Android Flash Filesystem" \
		-d "$(ANDROID_BUILD_TOP)/$(PRODUCT_OUT)/ramdisk-flash.img" \
		"$(ANDROID_BUILD_TOP)/$(PRODUCT_OUT)/uramdisk-flash.img"
	@echo "flashtool: `head -1 $(FLASH_RAMDISK_ROOT)/Changelog|cut -f 1 -d ' '`" >> \
		$(ANDROID_BUILD_TOP)/$(PRODUCT_OUT)/version.lst

ALL_PREBUILT += flashramdisk

