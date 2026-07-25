################################################################################
## Block-device / filesystem stack -- shared by any image that mounts a disk.
##
## Included with:   #include qnx-block.build.inc
##
## These four are the parts common to every block setup, whatever the transport:
## io-blk is the block layer, cam-disk the disk class driver, libcam the shared
## CAM library both use, and fs-qnx6 the filesystem module for a QNX6 image.
##
## The *driver* is deliberately not here, because that is exactly what differs:
## a guest uses devb-virtio against a vdev the host provides, a hypervisor host
## uses devb-ram (or devb-sdmmc against real hardware). The image that knows
## which one it wants lists it, and includes this for the rest.
##
## Add fs-dos.so in the image if it also has to read a FAT boot partition.
################################################################################

/lib/libcam.so=libcam.so
/lib/dll/io-blk.so=io-blk.so
/lib/dll/cam-disk.so=cam-disk.so
/lib/dll/fs-qnx6.so=fs-qnx6.so
