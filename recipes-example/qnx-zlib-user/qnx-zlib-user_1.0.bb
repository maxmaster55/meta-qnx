SUMMARY = "Links against the qnx-autotools zlib -- proves the sysroot handoff"
DESCRIPTION = "A one-line DEPENDS on zlib is all it takes to compile against \
zlib.h and link -lz: the header and library another recipe staged arrive in \
this recipe's sysroot automatically. The autotools-family counterpart of \
motor-controller depending on rpi-gpio."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://qnx-zlib-user.c"

inherit qnx-sdp

# This is the whole point: zlib's headers and library reach this recipe through
# the shared stage tree because of this one line, exactly as they would for any
# QNX library recipe. The sysroot -I/-L flags qnx-sdp adds do the rest.
DEPENDS = "zlib"

S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} -o qnx-zlib-user qnx-zlib-user.c ${LDFLAGS} -lz
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 qnx-zlib-user ${D}${QNX_STAGE_BINDIR}/qnx-zlib-user
}
