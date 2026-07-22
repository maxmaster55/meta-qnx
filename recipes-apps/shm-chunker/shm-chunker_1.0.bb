SUMMARY = "Shared-memory chunker/sender for the QNX motor demo"
DESCRIPTION = "First real application ported from the QNX hypervisor project's \
makefile build (src/shm_sender). Its Makefile already cross-compiles correctly \
for QNX, so this recipe drives it as-is rather than reimplementing the build: \
what Yocto adds is the environment, the staging, and the image dependency."
LICENSE = "CLOSED"

inherit qnx-sdp qnx-project-src

QNX_APP_SUBDIR = "src/shm_sender"

# The upstream Makefile hardcodes CC := qcc / CXX := q++ and builds the -V
# variant into its own CFLAGS. Passing CC/CXX on the command line overrides the
# makefile's assignment (make gives command-line variables precedence), which is
# what routes the build through the compiler this class configured.
#
# CFLAGS is deliberately NOT passed: the Makefile uses simple assignment, so
# overriding it would drop its -std and -V flags along with everything else.
EXTRA_OEMAKE = "CC='${CC}' CXX='${CXX}'"

# Its check-env target refuses to run without these, which this class exports.
do_compile() {
	oe_runmake -C ${S}
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 ${B}/shm_chunker ${D}${QNX_STAGE_BINDIR}/shm_chunker
}
