# freetype for QNX -- drop the libpng dependency.
#
# oe-core's default is "zlib pixmap", and pixmap means --with-png. libpng is
# portable and could be built, but nothing here needs freetype's PNG loader:
# freetype is in this build only because qtbase DEPENDS on it unconditionally.
# zlib is kept -- it is already proven on QNX (recipes-example/zlib).
#
# See recipes-ports/README.md for what belongs in this directory.
PACKAGECONFIG:qnx-aarch64le = "zlib"
