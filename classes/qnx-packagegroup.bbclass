# qnx-packagegroup.bbclass -- a named, reusable set of things to put in an image.
#
# The QNX analogue of packagegroup.bbclass. An image lists recipes in
# QNX_IFS_INSTALL; without something like this, two images that want the same
# ten components list the same ten names twice, and the day an eleventh is added
# one of them is quietly forgotten. That is the actual failure mode this
# prevents: a host and a guest that disagree about which SOME/IP runtime they
# carry, discovered on the target.
#
# A group is an ordinary recipe that builds nothing:
#
#     SUMMARY = "SOME/IP runtime"
#     LICENSE = "CLOSED"
#     inherit qnx-packagegroup
#     QNX_PACKAGEGROUP_INSTALL = "vsomeip commonapi-core commonapi-someip boost"
#
# and an image installs it by name, exactly like an application:
#
#     QNX_IFS_INSTALL = "qnx-packagegroup-someip my-app"
#
# Groups nest: a group may list other groups, and qnx-ifs.bbclass expands the
# whole tree. See "How the expansion works" below for why that is a drop-in file
# and not just DEPENDS.

inherit qnx-image-contract

# The members. These become DEPENDS, so building the group builds all of them
# and their files land in the installing image's sysroot.
QNX_PACKAGEGROUP_INSTALL ?= ""
DEPENDS += "${QNX_PACKAGEGROUP_INSTALL}"

# A group contributes no files of its own -- it is a name for other recipes --
# so there is nothing to harvest and nothing to check.
QNX_IFS_AUTO_ENTRIES = "0"
QNX_ELF_CHECK = "0"

# ...but the .install drop-in it writes still has to reach the image, and the
# drop-in directory lives in the stage tree.
SYSROOT_DIRS += "${QNX_STAGE_DIR}"

# Same reasoning as qnx-sdp: nothing here produces a Linux package, `bitbake
# world` should not try these against every machine, and they only make sense
# for a QNX machine.
inherit nopackages
INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"
COMPATIBLE_MACHINE = "qnx-aarch64le"

PACKAGE_ARCH = "${MACHINE_ARCH}"

# Nothing to fetch, configure, compile or strip.
do_fetch[noexec] = "1"
do_unpack[noexec] = "1"
do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"

# ---------------------------------------------------------------------------
# How the expansion works
# ---------------------------------------------------------------------------
# DEPENDS alone is not enough, and the reason is worth stating because it looks
# redundant. DEPENDS does get every member's files into the image's
# RECIPE_SYSROOT -- OE stages the full recursive closure, not just direct
# dependencies. What DEPENDS does not do is tell the image which *names* to read
# drop-ins for: qnx-ifs.bbclass walks QNX_IFS_INSTALL deliberately, rather than
# globbing the drop-in directory, so that the image's content is exactly what it
# asked for and not whatever else happens to be in the shared sysroot.
#
# So the membership list is also written out as a fragment, and the image reads
# it to extend its list. One file, and groups nest for free.
python qnx_packagegroup_write_install() {
    import os

    members = (d.getVar('QNX_PACKAGEGROUP_INSTALL') or '').split()
    if not members:
        bb.warn("%s inherits qnx-packagegroup but QNX_PACKAGEGROUP_INSTALL is "
                "empty, so installing it adds nothing" % d.getVar('PN'))
        return

    dropin_dir = d.getVar('D') + d.getVar('QNX_IFS_DROPIN_DIR')
    bb.utils.mkdirhier(dropin_dir)
    with open(os.path.join(dropin_dir, d.getVar('PN') + '.install'), 'w') as f:
        f.write('### %s\n' % d.getVar('PN'))
        for member in members:
            f.write(member + '\n')
}
do_install[postfuncs] += "qnx_packagegroup_write_install"
qnx_packagegroup_write_install[vardeps] += "QNX_PACKAGEGROUP_INSTALL"

do_install[dirs] = "${D}"
