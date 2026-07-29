SUMMARY = "Filesystem creation and repair tools"
DESCRIPTION = "fdisk, mkqnx6fs, mkdosfs and devf-ram -- partitioning and making \
filesystems on the target rather than building them into an image. The block \
stack itself is qnx-block; this is what you use once it is running."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-block"

QNX_COMPONENT_FILES = "\
    fdisk \
    mkqnx6fs \
    mkdosfs \
    devf-ram \
    flashctl \
    umount \
    sync \
"
