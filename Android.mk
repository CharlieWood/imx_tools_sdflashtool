LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

flashramdisk: FLASH_RAMDISK_ROOT := $(LOCAL_PATH)
flashramdisk: $(PRODUCT_OUT)/uramdisk-flash.img

$(PRODUCT_OUT)/uramdisk-flash.img: | $(ACP)
	$(FLASH_RAMDISK_ROOT)/bin/mkbootfs $(FLASH_RAMDISK_ROOT)/root > \
		$(PRODUCT_OUT)/ramdisk-flash.img
	@echo "Install: $@"
	$(TARGET_TOOLS_PREFIX)mkimage \
		-A arm -O linux -T ramdisk -C none -a 0x90308000 \
		-n "Android Flash Filesystem" \
		-d "$(PRODUCT_OUT)/ramdisk-flash.img" \
		"$(PRODUCT_OUT)/uramdisk-flash.img"

ALL_PREBUILT += flashramdisk

