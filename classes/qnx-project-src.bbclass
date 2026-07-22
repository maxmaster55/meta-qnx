# qnx-project-src.bbclass -- build an application straight out of a working tree.
#
# The applications in the QNX hypervisor project live in their own repository
# (several as git submodules tracking a branch), and are edited constantly. A
# recipe that fetched a pinned revision would mean committing and bumping a
# SRCREV to see a change, which is exactly the friction that makes people go
# back to running make by hand.
#
# So these recipes build the working tree in place via OE's externalsrc. Point
# QNX_PROJECT_SRC at the checkout in local.conf:
#
#     QNX_PROJECT_SRC = "/path/to/Qnx_Hypervisor_rbye"
#
# Recipes set QNX_APP_SUBDIR to their directory under it. Builds are out of tree
# where the build system allows it, and otherwise land in the same build/ dir
# the project's own makefiles use -- which is already gitignored there.
#
# Trade-off worth knowing: externalsrc deliberately disables sstate for these
# recipes, since a working tree has no signature to hash. do_compile therefore
# runs every time. That is the right default while porting; a recipe that has
# stabilised can be switched to a real SRC_URI with a pinned SRCREV.

inherit externalsrc

QNX_PROJECT_SRC ??= ""
QNX_APP_SUBDIR ??= ""

EXTERNALSRC = "${QNX_PROJECT_SRC}/${QNX_APP_SUBDIR}"
EXTERNALSRC_BUILD ?= "${EXTERNALSRC}/build"

python () {
    src = d.getVar('QNX_PROJECT_SRC')
    sub = d.getVar('QNX_APP_SUBDIR')

    if not src:
        raise bb.parse.SkipRecipe(
            "QNX_PROJECT_SRC is not set. Point it at a checkout of the QNX "
            "application tree in local.conf to build the application recipes.")
    if not sub:
        bb.fatal("%s inherits qnx-project-src but sets no QNX_APP_SUBDIR"
                 % d.getVar('PN'))

    path = os.path.join(src, sub)
    if not os.path.isdir(path):
        raise bb.parse.SkipRecipe(
            "%s not found -- QNX_PROJECT_SRC may point at the wrong tree, or "
            "a submodule may not be checked out" % path)
}
