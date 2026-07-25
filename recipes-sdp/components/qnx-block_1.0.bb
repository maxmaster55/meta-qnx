SUMMARY = "Block-device and filesystem stack"
DESCRIPTION = "io-blk, the disk class driver and the QNX6 filesystem module -- \
the parts of a block setup that are the same whatever the transport is. The \
devb-* driver itself belongs to the image that knows what hardware it has."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# io-blk is the block layer, cam-disk the disk class driver, libcam the CAM
# library both use, fs-qnx6 the filesystem module for a QNX6 image. All four are
# dlopen'd by a devb-* driver rather than linked, so none appears in anyone's
# DT_NEEDED.
#
# The *driver* is deliberately absent: a guest uses devb-virtio against a vdev
# the host provides, a hypervisor host devb-ram or devb-sdmmc against real
# hardware. The image that knows which one it wants installs it alongside this.
QNX_COMPONENT_FILES = "\
    libcam.so \
    io-blk.so \
    cam-disk.so \
    fs-qnx6.so \
"
