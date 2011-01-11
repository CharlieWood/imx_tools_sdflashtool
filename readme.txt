1. 运行mkimg.sh可以生成uramdisk.img

2. SD卡第一个分区必须是vfat分区

SD卡目录结构，根目录下建立update目录，
Root
 └─ update
    ├── bin            <==== boot所需要的二进制文件
    │   ├── uImage           <==== boot kenrel，可以直接使用正常启动的kernel
    │   └── uramdisk.img     <==== boot ramdisk, 从这个project获得
    │
    ├── images         <==== 所有要烧写的image文件和配置文件
    │   ├── md5sum.txt          <==== MD5校验文件
    │   ├── u-boot-no-padding.bin
    │   ├── uImage
    │   ├── uramdisk.img
    │   ├── uImage-recovery
    │   ├── uramdisk-recovery.img
    │   ├── system.img
    │   └── userdata.img
    │   
    └── logs
        └── flash.log  <==== 烧写过程中的Log文件


配置文件：

repartition: 强制重新创建分区

clearubootenv: 清除u-boot环境变量

partition.cfg: 与repartition配合，设置各分区default size
  格式：
		boot_space=32
		system_space=250
		data_space=1024
		cache_space=128
		recovery_space=16

