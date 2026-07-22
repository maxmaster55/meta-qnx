SUMMARY = "Minimal bootable QNX IFS containing the Yocto-built qnx-hello"
DESCRIPTION = "Assembles an aarch64le QNX image filesystem with mkifs. The single \
DEPENDS line below is what replaces the hand-rolled .build-file dependency \
scraping in the makefile-based QNX build: bitbake reruns mkifs when qnx-hello \
changes, without being told which files the .build file stages."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "qnx-hello"

SRC_URI = "file://qnx-hello.build"

inherit qnx-ifs

# scarthgap has no UNPACKDIR, so file:// sources land directly in WORKDIR.
S = "${WORKDIR}"
B = "${WORKDIR}/build"

QNX_IFS_NAME = "qnx-hello"
QNX_IFS_BUILDFILE = "${S}/qnx-hello.build"

do_configure[noexec] = "1"
do_compile[noexec] = "1"
