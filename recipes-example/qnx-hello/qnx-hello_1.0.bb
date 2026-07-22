SUMMARY = "Hello-world binary for QNX, compiled with the SDP's qcc"
DESCRIPTION = "Smallest possible proof that bitbake can drive qcc. Staged into \
the QNX stage tree so that an IFS recipe picks it up through a plain DEPENDS."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://qnx-hello.c"

inherit qnx-sdp

# scarthgap has no UNPACKDIR (that arrived in styhead), so file:// sources are
# unpacked straight into WORKDIR.
S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} -o qnx-hello qnx-hello.c
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 qnx-hello ${D}${QNX_STAGE_BINDIR}/qnx-hello
}
