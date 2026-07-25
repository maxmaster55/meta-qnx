SUMMARY = "QNX IFS whose entire payload comes from stock Yocto layers"
DESCRIPTION = "Proof that a recipe nobody here wrote can be built for QNX and \
put in an image. Everything installed below is an unmodified upstream recipe \
taken from oe-core: it is compiled with qcc by qnx-toolchain.bbclass, it writes \
the same image drop-in a meta-qnx recipe writes, and this image installs it by \
name. No wrapper recipe, no patch, and no entry in the build file. See \
docs/reusing-layers.md."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://qnx-reuse.build.in"

inherit qnx-ifs

# Stock oe-core recipes. Not wrappers around them -- these names resolve to
# poky/meta/recipes-*/ exactly as they would in a Linux build.
#
# One recipe per build system, because that is where the differences are:
#
#   bzip2  (autotools) -- the awkward shape rather than the easy one. It builds
#          a shared library, which is where libtool's GNU-ld probe has to be
#          right, plus a set of binaries and a pile of symlinks between them.
#   json-c (cmake)     -- autotools asks the compiler what it is; cmake is told,
#          so it is the one that catches a wrong CMAKE_SYSTEM_NAME or a lost
#          -V<variant>. Both of those silently produce a *working build* of the
#          wrong thing, so having a cmake recipe in a real image is the check.
QNX_IFS_INSTALL = "bzip2 json-c"

# scarthgap has no UNPACKDIR, so file:// sources land directly in WORKDIR.
S = "${WORKDIR}"
B = "${WORKDIR}/build"

QNX_IFS_NAME = "qnx-reuse"
QNX_IFS_TEMPLATE = "${S}/qnx-reuse.build.in"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

python () {
    # Without qnx-toolchain, "bzip2" resolves to a recipe being built for Linux
    # with Yocto's cross-gcc: it would either fail or, worse, quietly put x86
    # binaries in an aarch64 image. Skipping with the reason beats both.
    if 'qnx-toolchain' not in (d.getVar('INHERIT') or '').split():
        raise bb.parse.SkipRecipe(
            "this image is built from stock Yocto recipes, which needs the qcc "
            "toolchain applied to them. Add to conf/local.conf:\n"
            '  INHERIT += "qnx-toolchain"\n'
            '  DISTRO_FEATURES:remove = "ptest"\n'
            "See meta-qnx/docs/reusing-layers.md.")
}
