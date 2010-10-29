运行mkimg.sh生成uramdisk.img

SD卡第一个分区必须是vfat分区

SD卡目录结构，根目录下建立update目录，
Root
└── update
    ├── bin            <==== boot所需要的二进制文件
    │   ├── uImage           <==== boot kenrel，可以直接使用正常启动的kernel
    │   └── uramdisk.img     <==== boot ramdisk, 从这个目录生成
    │
    ├── images         <==== 所有要烧写的image文件
    │   ├── uImage
    │   ├── uramdisk.img
    │   ├── system.img
    │   ├── userdata.img
    │   ├── cache.img
    │   └── recovery.img
    │   
    └── logs
        └── flash.log  <==== 烧写过程中的Log文件

U-boot设置：
bootdelay=3
baudrate=115200
loadaddr=0x90800000
uboot_addr=0xa0000000
uboot=u-boot.bin
kernel=uImage
loadaddr=0x90800000
rd_loadaddr=0x90B00000
bootargs_base=setenv bootargs console=ttymxc0,115200
bootargs_android=setenv bootargs ${bootargs} init=/init androidboot.console=ttymxc0 di1_primary calibration
bootcmd_SD1=run bootargs_base bootargs_android bootargs_SD
bootargs_SD=setenv bootargs ${bootargs}
bootargs=console=ttymxc0,115200 init=/init androidboot.console=ttymxc0 di1_primary calibration
bootcmd=run bootcmd_SD1 bootcmd_SD2
bootcmd_SD2=fatload mmc 0:1 0x90800000 /update/bin/uimage;fatload mmc 0:1 0x90B00000 /update/bin/uramdisk.img;bootm 0x90800000 0x90B00000
filesize=25F3F0
stdin=serial
stdout=serial
stderr=serial

