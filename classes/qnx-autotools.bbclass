# qnx-autotools.bbclass -- build a ./configure + make project with the QNX SDP toolchain.
#
# The sibling of qnx-cmake and qnx-meson for the autotools / hand-rolled-configure
# family, which is most of meta-openembedded and oe-core. Deliberately NOT built on
# OE's autotools.bbclass: that assumes Yocto's own cross-toolchain, its
# autoconf-native/gnu-configize, its sysroot layout and packaging -- all of which
# qnx-sdp.bbclass switches off. Driving configure directly is less work than
# unpicking those assumptions, exactly as with qnx-cmake.
#
# Verified against UNMODIFIED upstream zlib: a portable ./configure library
# configures and builds with qcc through this class with no patches at all --
# configure detects qcc, probes QNX correctly (off64_t, fseeko, ...) and produces
# an aarch64 QNX .so. The catch is the usual one: code that assumes Linux/glibc
# (a /proc layout, a glibc-only extension, a Linux socket option) still needs the
# same porting a hand build would. The class removes the toolchain plumbing, not
# the portability work.

inherit qnx-sdp

B = "${WORKDIR}/build"

# The cross triplet handed to configure as --host, which is what puts autoconf
# into cross mode so it never tries to run a target binary. Derived from the
# machine's tool prefix (aarch64-unknown-nto-qnx8.0.0-) with the trailing dash
# removed; config.sub recognises nto-qnx. A recipe whose configure is hand-rolled
# and rejects --host (zlib is one) sets this to "" to drop it.
QNX_CONFIGURE_HOST ?= "${@d.getVar('QNX_TOOL_PREFIX')[:-1]}"

# --build/--host together, or nothing when the host is cleared. Kept as one
# variable so a non-standard configure can switch the whole cross-mode pair off.
QNX_CONFIGURE_HOST_ARGS ?= "${@('--build=%s --host=%s' % (d.getVar('BUILD_SYS'), d.getVar('QNX_CONFIGURE_HOST'))) if d.getVar('QNX_CONFIGURE_HOST') else ''}"

# The install directories, mapped onto the stage tree so output lands in the shape
# the staging contract wants (see qnx-sdp.bbclass): binaries and libraries under
# ${PROCESSOR}/, headers under usr/include. --prefix alone would put everything
# under ${QNX_STAGE_DIR}/{bin,lib,include}, which is neither the mkifs layout nor
# the sysroot layout. A recipe whose configure does not accept one of these
# overrides the whole variable (again, zlib).
QNX_AUTOTOOLS_DIRS ?= "\
    --bindir=${QNX_STAGE_BINDIR} \
    --sbindir=${QNX_STAGE_SBINDIR} \
    --libdir=${QNX_STAGE_LIBDIR} \
    --includedir=${QNX_STAGE_INCLUDEDIR} \
"

# Extra ./configure arguments, the analogue of OE's EXTRA_OECONF.
EXTRA_OECONF ?= ""

# Where configure lives. A project that keeps it in a subdirectory, or uses a
# differently named script, overrides this.
QNX_CONFIGURE_SCRIPT ?= "${S}/configure"

# pkg-config, mirroring qnx-meson: a library produced by another qnx recipe is
# found through the stage tree's pkgconfig dir, and OE's sysroot rewriting is
# turned off because the .pc files there already hold real absolute paths.
export PKG_CONFIG_LIBDIR = "${RECIPE_SYSROOT}${QNX_STAGE_USRLIBDIR}/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR = ""

# Defined directly rather than via EXPORT_FUNCTIONS: that mechanism derives sh
# function names from the class name, and a dash is illegal in one (same reason as
# qnx-cmake). A recipe needing different behaviour overrides the task as usual.
do_configure() {
	${QNX_CONFIGURE_SCRIPT} \
		${QNX_CONFIGURE_HOST_ARGS} \
		--prefix=${QNX_STAGE_DIR} \
		${QNX_AUTOTOOLS_DIRS} \
		${EXTRA_OECONF}
}

do_compile() {
	oe_runmake
}

do_install() {
	oe_runmake DESTDIR=${D} install
}
