# qnx-src.bbclass -- get an application's source from its git repository.
#
# Fetches from the remote by default and tracks the branch head, so a build
# picks up whatever was pushed last:
#
#     inherit qnx-src
#     QNX_SRC_REPO = "git://github.com/you/thing.git;protocol=https"
#     QNX_SRC_BRANCH = "main"
#     QNX_SRC_SUBDIR = "src/thing"     # optional, for a repo of many apps
#
# Tracking a branch head is a deliberate trade-off. `bitbake` will resolve the
# branch on every parse, which needs the network and means two builds a minute
# apart can produce different output. That is what QNX_SRC_REV is for: pin it to
# a commit and the build becomes reproducible and offline-capable.
#
#     QNX_SRC_REV = "c19814a7c0b4a0c4b0e5e0e1f2a3b4c5d6e7f8a9"
#
# To work on an application, point QNX_SRC_LOCAL at a checkout and the recipe
# builds that tree in place instead of fetching -- no commit needed to see a
# change. Set it per-recipe, or globally in local.conf:
#
#     QNX_SRC_LOCAL:pn-frame-router = "/path/to/checkout"
#
# Note what changes when you do: externalsrc has no revision to hash, so those
# recipes lose sstate and rebuild every time. That is the right default while
# editing and the wrong one for CI, which is why fetching is the default here.

QNX_SRC_REPO ?= ""
QNX_SRC_BRANCH ?= "main"
QNX_SRC_REV ?= "${AUTOREV}"
QNX_SRC_SUBDIR ?= ""
QNX_SRC_LOCAL ?= ""

# Building a working tree is the exception, so the class it needs is inherited
# only when asked for. inherit_defer evaluates after the recipe has been parsed,
# which is what lets this depend on a recipe-set variable at all.
inherit_defer ${@'externalsrc' if d.getVar('QNX_SRC_LOCAL') else ''}

# ---------------------------------------------------------------------------
# Remote
# ---------------------------------------------------------------------------
SRC_URI = "${@'' if d.getVar('QNX_SRC_LOCAL') else d.getVar('QNX_SRC_REPO')}"
SRCREV = "${QNX_SRC_REV}"

# A branch head has no version of its own; +git marks it as such.
PV .= "${@'' if d.getVar('QNX_SRC_LOCAL') else '+git'}"

S = "${@os.path.join(d.getVar('WORKDIR'), 'git', d.getVar('QNX_SRC_SUBDIR') or '').rstrip('/')}"

# ---------------------------------------------------------------------------
# Local working tree
# ---------------------------------------------------------------------------
EXTERNALSRC = "${@os.path.join(d.getVar('QNX_SRC_LOCAL') or '', d.getVar('QNX_SRC_SUBDIR') or '').rstrip('/')}"
# In-tree by default, because the makefiles these recipes drive write into a
# ./build directory relative to the source. A recipe whose build system supports
# out-of-tree builds (cmake, meson) should set this to ${WORKDIR}/build.
EXTERNALSRC_BUILD ?= "${EXTERNALSRC}/build"

# externalsrc drops oe-workdir/oe-logs symlinks beside the sources it builds.
# That is someone else's git repository: it tries to hide them via
# .git/info/exclude, but the result is still untracked clutter in a tree the
# build has no business modifying. The logs remain under tmp/work.
EXTERNALSRC_SYMLINKS = ""

python () {
    local = d.getVar('QNX_SRC_LOCAL')
    subdir = d.getVar('QNX_SRC_SUBDIR') or ''

    if local:
        path = os.path.join(local, subdir)
        if not os.path.isdir(path):
            raise bb.parse.SkipRecipe(
                "QNX_SRC_LOCAL is set but %s does not exist. Point it at a "
                "checkout of the application tree, or unset it to fetch from "
                "%s instead." % (path, d.getVar('QNX_SRC_REPO') or 'the remote'))
        return

    if not d.getVar('QNX_SRC_REPO'):
        bb.fatal("%s inherits qnx-src but sets neither QNX_SRC_REPO nor "
                 "QNX_SRC_LOCAL" % d.getVar('PN'))
}
