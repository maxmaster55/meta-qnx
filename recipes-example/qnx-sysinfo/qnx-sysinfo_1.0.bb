SUMMARY = "Prints QNX kernel/machine info, built with the SDP's qcc"
DESCRIPTION = "A second application, existing to demonstrate that adding one to an \
image costs exactly one word in QNX_IFS_INSTALL. Note what this recipe does NOT \
contain: any list of files, any path inside the image, any reference to a .build \
file. Its /bin/qnx-sysinfo entry is derived from do_install automatically."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://qnx-sysinfo.c"

inherit qnx-sdp

QNX_IFS_STARTUP_CMD = "qnx-sysinfo"

# Runs after qnx-hello so the system info appears last in the boot log.
# For a real image with drivers, list those here instead.
QNX_IFS_STARTUP_AFTER = "qnx-hello"

# scarthgap has no UNPACKDIR (that arrived in styhead), so file:// sources are
# unpacked straight into WORKDIR.
S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} -o qnx-sysinfo qnx-sysinfo.c
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 qnx-sysinfo ${D}${QNX_STAGE_BINDIR}/qnx-sysinfo
}
