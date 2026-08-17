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
# PNG is enabled below through EXTRA_OECMAKE rather than here, because
# PACKAGECONFIG[png] means *system* libpng and there is no system libpng on
# QNX. See the FEATURE_png block further down.
QNX_QTBASE_PACKAGECONFIG ?= "gui"
PACKAGECONFIG:qnx-aarch64le = "${QNX_QTBASE_PACKAGECONFIG}"

# --- OpenGL ----------------------------------------------------------------
# An explicit decision is not optional the moment gui is on: Qt treats OpenGL as
# required unless told otherwise and fails configure with "The OpenGL
# functionality tests failed!" -- it does not quietly fall back.
#
# This is a knob rather than a fixed "no" because whether there is a GL stack is
# a property of the BOARD, not of QNX. Both answers are real here:
#
#   no    Qt Quick then has no RHI backend and the application must run with
#         QT_QUICK_BACKEND=software. That renders, but the software backend has
#         no shader support, so QtQuick.Effects (MultiEffect) and every
#         layer.enabled item silently draw NOTHING -- no warning, no error. A UI
#         that leans on them comes out looking like a plainer design rather than
#         a broken one, which is a genuinely hard failure to diagnose.
#
#   es2   OpenGL ES 2. Needs libEGL/libGLESv2 and their headers, which SDP 8
#         ships in target/qnx/aarch64le/usr/lib and usr/include -- Qt finds them
#         the same way it finds libscreen, so nothing here says where they are.
#         The board also needs a driver behind them at RUNTIME; the SDP
#         libraries are a dispatch layer and resolve to nothing on their own.
#
# PACKAGECONFIG[gles2] is the wrong lever, for the same reason PACKAGECONFIG[png]
# is: it carries DEPENDS on virtual/libgles2 and virtual/egl, and there is no
# Yocto recipe providing either on QNX -- they come from the SDP. So the choice
# is passed straight to Qt, mirroring what PACKAGECONFIG[no-opengl] did.
# INPUT_opengl alone is not enough, and the reason is easy to miss. meta-qt6
# derives -DFEATURE_opengles2=OFF and -DFEATURE_opengl_desktop=OFF from
# PACKAGECONFIG not containing gles2/opengl, and emits them EARLIER on the same
# command line. Setting only INPUT_opengl leaves those OFF entries sitting in the
# cache against it. The FEATURE_ overrides below are appended after them, and
# for one cmake invocation the last -D on the line is the one that sticks.
QNX_QTBASE_OPENGL ?= "no"
QNX_QTBASE_OPENGL_CMAKE = "-DINPUT_opengl=${QNX_QTBASE_OPENGL}"
QNX_QTBASE_OPENGL_CMAKE:append = "${@' -DFEATURE_opengles2=ON -DFEATURE_egl=ON' if d.getVar('QNX_QTBASE_OPENGL') == 'es2' else ''}"
EXTRA_OECMAKE:append:qnx-aarch64le = " ${QNX_QTBASE_OPENGL_CMAKE}"

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

# PNG decoding, from the copies Qt carries in src/3rdparty rather than from the
# system. Without this QtGui has no PNG decoder at all -- it is compiled in, not
# a plugin -- and an application fails where it draws, with a message that
# sounds like a missing plugin and is not:
#
#     QML Image: Error decoding: qrc:/images/car.png: Unsupported image format
#
# PACKAGECONFIG[png] is the wrong lever: it sets FEATURE_system_png, and there
# is no system libpng here. Adding it (and zlib, which libpng needs) makes cmake
# hunt for target libraries that the SDP does not ship and the zlib recipe does
# not stage for QNX, so it resolves them in recipe-sysroot-native instead and
# the link fails on an architecture mismatch naming neither png nor Qt:
#
#     aarch64-unknown-nto-qnx8.0.0-ld: recipe-sysroot-native/usr/lib/libz.so:
#       error adding symbols: file in wrong format
#
# system_zlib is turned off for the same reason: bundled libpng needs zlib, and
# Qt's bundled copy is the only one that exists for this target.
EXTRA_OECMAKE:append:qnx-aarch64le = " -DFEATURE_png=ON \
                                       -DFEATURE_system_png=OFF \
                                       -DFEATURE_system_zlib=OFF"

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
