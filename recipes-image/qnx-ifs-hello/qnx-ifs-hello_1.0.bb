SUMMARY = "Minimal bootable QNX IFS, populated from QNX_IFS_INSTALL"
DESCRIPTION = "Assembles an aarch64le QNX image filesystem with mkifs. The .build \
file handed to mkifs is generated from the recipes listed below, so adding an \
application to the image means adding its name here and nothing else -- no image \
file is edited, and no list of files is duplicated."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://qnx-hello.build.in"

inherit qnx-ifs

# The only line that changes when an application is added to the image.
# Analogous to IMAGE_INSTALL on Linux.
QNX_IFS_INSTALL = "qnx-hello qnx-sysinfo shm-chunker rpi-gpio"

# scarthgap has no UNPACKDIR, so file:// sources land directly in WORKDIR.
S = "${WORKDIR}"
B = "${WORKDIR}/build"

QNX_IFS_NAME = "qnx-hello"
QNX_IFS_TEMPLATE = "${S}/qnx-hello.build.in"

do_configure[noexec] = "1"
do_compile[noexec] = "1"
