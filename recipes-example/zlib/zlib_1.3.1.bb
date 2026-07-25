SUMMARY = "zlib compression library (QNX) -- worked example for qnx-autotools"
DESCRIPTION = "Unmodified upstream zlib, cross-built for QNX with qcc through \
qnx-autotools. The point it makes: a portable ./configure library needs no QNX \
patches -- inherit the class, hand it the upstream tarball, and it stages libz \
and zlib.h so other recipes can DEPENDS on it and images can install it. This is \
the autotools-family counterpart of rpi-gpio (qnx-cmake)."
HOMEPAGE = "https://zlib.net"
LICENSE = "Zlib"
LIC_FILES_CHKSUM = "file://zlib.h;beginline=6;endline=23;md5=5377232268e952e9ef63bc555f7aa6c0"

# Unmodified upstream tarball -- no patches, no QNX fork.
SRC_URI = "https://zlib.net/fossils/zlib-${PV}.tar.gz"
SRC_URI[sha256sum] = "9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"

inherit qnx-autotools

S = "${WORKDIR}/zlib-${PV}"

# zlib's configure is hand-rolled, not GNU autoconf: it ignores --build/--host,
# does not accept --bindir/--sbindir, and rejects the --disable-static that OE's
# base config appends to EXTRA_OECONF for real autotools. So drop the cross-mode
# pair (it picks up CC=qcc from the environment anyway), give it only the two dir
# flags it understands, and clear DISABLE_STATIC. --uname=GNU selects the
# versioned-.so build other software expects (libz.so.1 -> libz.so.1.3.1).
#
# A real GNU autoconf library needs none of these overrides -- the class defaults
# (--build/--host, the full dir set, --disable-static) are exactly for that case.
QNX_CONFIGURE_HOST = ""
QNX_AUTOTOOLS_DIRS = "--libdir=${QNX_STAGE_LIBDIR} --includedir=${QNX_STAGE_INCLUDEDIR}"
DISABLE_STATIC = ""
EXTRA_OECONF = "--shared --uname=GNU"
