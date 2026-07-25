# qtbase for QNX -- see meta-qnx/docs/qt6.md
#
# This file exists only when meta-qt6 is in the build (BBFILES_DYNAMIC in
# meta-qnx/conf/layer.conf), so meta-qnx keeps LAYERDEPENDS = "core".
#
# Everything here is keyed on the machine override. MACHINE is in OVERRIDES and
# CLASSOVERRIDE (class-native) comes *after* it, so qtbase-native keeps its own
# settings and still builds host tools -- moc, rcc, qmlcachegen -- with gcc.
# That native Qt is the whole reason to prefer meta-qt6 over a hand-rolled
# recipe: QT_HOST_PATH is wired up by qt6-cmake.bbclass for free.

# --- what Qt is allowed to depend on ---------------------------------------
# meta-qt6's PACKAGECONFIG_DEFAULT is a Linux runtime closure: dbus, glib,
# fontconfig, harfbuzz, icu, libinput, udev, xkbcommon, openssl -- plus
# PACKAGECONFIG_GRAPHICS appends linuxfb unconditionally. None of that exists on
# QNX. Replacing the list wholesale is both simpler and more honest than
# subtracting eleven entries, and it makes the supported set one readable line.
#
# The supported set, smallest first:
#
#   ""            QtCore, QtNetwork, QtXml, QtSql, QtConcurrent, QtTest.
#                 Verified: links libslog2/libfsnotify/libeventfd, i.e. Qt's
#                 real QNX backends rather than its Linux ones.
#   "gui no-opengl"
#                 adds QtGui. Needs a QPA platform plugin, which on QNX means
#                 Screen (libscreen, from the SDP) -- this is where a Linux
#                 build would have used linuxfb, and the reason linuxfb is not
#                 in the list above.
#
# no-opengl is not optional the moment gui is on. Qt treats OpenGL as required
# unless told otherwise and fails configure with "The OpenGL functionality tests
# failed!" -- it does not quietly fall back. Turning it off is also what the
# hand-written qt6-qnx recipe does (-DINPUT_opengl=no). A board with a GPU
# overrides this whole variable rather than editing here.
QNX_QTBASE_PACKAGECONFIG ?= "gui no-opengl"
PACKAGECONFIG:qnx-aarch64le = "${QNX_QTBASE_PACKAGECONFIG}"

# --- features Qt gets wrong for QNX ----------------------------------------
# libresolv: Qt's DNS lookup wants glibc's resolver entry points
# (__res_nmkquery, __res_setservers). QNX has no libresolv and does not export
# those names, so QtNetwork builds and *stages* fine, and the failure lands on
# the next module to link against it -- qtdeclarative, as "undefined reference"
# from inside libQt6Network, which reads like QtNetwork is corrupt.
#
# -DFEATURE_libresolv=OFF is what the hand-written qt6-qnx recipe passes, and
# is the reason it does.
EXTRA_OECMAKE:append:qnx-aarch64le = " -DFEATURE_libresolv=OFF"

# --- QNX-specific link fixups ----------------------------------------------
# Not folded into qnx-toolchain.bbclass on purpose: these are Qt's problems, not
# every CMake recipe's.
#
#   eventfd -- QNX 8 ships eventfd()/eventfd_read()/eventfd_write() in a
#   standalone libeventfd.so; on Linux they are in libc. QtCore references them,
#   so without this the link fails with "undefined reference to `eventfd'".
#   The _INIT variables are the toolchain-file way to *add* to the linker flags
#   rather than replace whatever Qt's own build computed.
#
#   TRY_COMPILE_TARGET_TYPE -- CMake's default compiler check links a full
#   executable. Building one this early, before Qt has worked out its own link
#   line, is what CMAKE_TRY_COMPILE_TARGET_TYPE exists to avoid.
#
# Both are what the hand-written toolchain file in meta-qnx-guest's qt6-qnx
# recipe carries, which is the closest thing to a known-good reference for Qt on
# QNX 8 that this tree has.
cmake_do_generate_toolchain_file:append:qnx-aarch64le() {
	cat >> ${WORKDIR}/toolchain.cmake <<EOF

# --- appended by meta-qnx's qtbase bbappend ---
set( CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY )
string( APPEND CMAKE_EXE_LINKER_FLAGS_INIT    " -leventfd" )
string( APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " -leventfd" )
string( APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " -leventfd" )
EOF
}
