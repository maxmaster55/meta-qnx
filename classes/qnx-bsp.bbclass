# qnx-bsp.bbclass -- unpack a BSP the Software Center delivered as a zip.
#
#     inherit qnx-bsp
#     QNX_SDP_REQUIRES = "com.qnx.qnx800.bsp.hw.raspberrypi_bcm2712_rpi5"
#     QNX_BSP_ZIP_GLOB = "BSP_raspberrypi-bcm2712-rpi5_*.zip"
#
# A BSP is not in ${QNX_TARGET}. The Software Center drops it under
# ${QNX_SDP_ROOT}/bsp as an archive carrying prebuilt binaries alongside the
# source they were built from, so mkifs cannot see any of it. This class unpacks
# the prebuilt half into the stage tree, which is laid out exactly as `mkifs -r`
# wants (<root>/aarch64le/{bin,sbin,boot/sys}) -- after which an image that
# DEPENDS on the recipe can name those binaries by bare name.
#
# Two BSPs use this: the Raspberry Pi 5 board BSP, which is where a host image's
# drivers come from, and the hypervisor guest BSP, which is where a guest's
# shmem-guest and wdtkick come from. They differ only in which archive they name.

inherit qnx-sdp

# Where the Software Center puts them.
#
# ??= and not ?=, and the distinction matters in a class. `inherit` is processed
# where it appears, so a class's `?=` is applied BEFORE the rest of the recipe
# is parsed -- and a recipe's own `?=` further down then finds the variable
# already set and does nothing. `??=` is the weaker default that a recipe's `?=`
# still overrides, which is what a recipe author expects.
QNX_BSP_ZIP_DIR ??= "${QNX_SDP_ROOT}/bsp"

# QNX_BSP_ZIP_GLOB is deliberately NOT given a default here, not even an empty
# one. A `?=` in a class is applied when the class is inherited, which is before
# the rest of the recipe is parsed -- so a `?=` here would win over the recipe's
# own `?=` further down the file, and the recipe's value would be silently
# discarded. With an empty string the pattern became "<zipdir>/", glob matched
# the directory itself, and the failure surfaced far from its cause:
#
#     IsADirectoryError: [Errno 21] Is a directory: '.../qnx-sdp/bsp/'
#
# Left unset, a recipe that forgets it is caught by the guard at the bottom
# instead.

# The half of the archive worth having. The other half is source and .sym files
# -- tens of megabytes that no image consumes. ??= for the reason above: a
# recipe building its BSP from source would set this to "install" with a `?=`.
QNX_BSP_TREE ??= "prebuilt"

# Paths inside the staged processor tree to drop, relative to it.
#
# libstartup.a is what you link a startup program against. Nothing here builds
# one -- every image names a prebuilt startup on its boot line -- so it is a
# build-time artefact with no consumer, and every BSP ships its own copy at the
# same path. An image installing two BSPs then gets:
#
#     The file /qnx-stage/aarch64le/usr/lib/libstartup.a is installed by both
#     qnx-rpi5-bsp and qnx-hyp-guest-bsp, aborting
#
# which is Yocto correctly refusing to let two recipes own one path. Dropping it
# is better than picking a winner: the guest image legitimately needs binaries
# from both the board BSP and the guest BSP.
QNX_BSP_EXCLUDE ??= "usr/lib/libstartup.a"

S = "${WORKDIR}/bsp"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

# Nothing to fetch: the zip is already on disk, put there by install_sdp.
SRC_URI = ""

# The image names what it wants from a BSP by hand, in its own build file: it
# uses a handful of the binaries and a startup that has to appear in the boot
# line, not a harvested list of everything the BSP ships.
QNX_IFS_AUTO_ENTRIES = "0"

# Which means a BSP contributes no records at all -- not automatic ones and no
# QNX_IFS_EXTRA_ENTRIES either. Saying so keeps the image's "contributes nothing
# to the image" check meaningful, instead of firing on every BSP an image
# installs and training people to ignore it.
QNX_IFS_STAGE_ONLY = "1"

# These are QNX's own aarch64 binaries; there is no build here whose ${CC} could
# have gone wrong, and the check would only walk them for nothing.
QNX_ELF_CHECK = "0"


python do_unpack() {
    import glob
    import os
    import shutil
    import zipfile

    pattern = qnx_bsp_pattern(d)
    found = sorted(p for p in glob.glob(pattern) if os.path.isfile(p))

    if not found:
        bb.fatal("no BSP archive matching %s (checked at parse time too, so "
                 "reaching here means it vanished mid-build)" % pattern)

    # Newest by name: the trailing SVN/build numbers sort in release order, so
    # an SDP carrying two BSP generations uses the later one.
    archive = found[-1]
    if len(found) > 1:
        bb.note("%s: %d BSP archives present, using %s"
                % (d.getVar('PN'), len(found), os.path.basename(archive)))

    workdir = d.getVar('S')
    if os.path.isdir(workdir):
        shutil.rmtree(workdir)
    bb.utils.mkdirhier(workdir)

    tree = d.getVar('QNX_BSP_TREE')
    prefix = tree + '/'

    # Python's zipfile rather than the unzip command, which is not in bitbake's
    # sanitized PATH and would have to be added to HOSTTOOLS -- a fatal
    # requirement on every build, for one recipe in one layer.
    #
    # The catch is that ZipFile.extract() applies the process umask and drops
    # the executable bit, which for a tree of drivers is silently wrong: they
    # install, they land in the image, and the board reports an exec failure.
    # The mode is in the archive, in the top 16 bits of external_attr, so it is
    # restored explicitly.
    extracted = 0
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            if not info.filename.startswith(prefix):
                continue
            zf.extract(info, workdir)
            if info.is_dir():
                continue
            mode = info.external_attr >> 16
            if mode:
                os.chmod(os.path.join(workdir, info.filename), mode & 0o7777)
            extracted += 1

    unpacked = os.path.join(workdir, tree, d.getVar('QNX_PROCESSOR'))
    if not os.path.isdir(unpacked):
        bb.fatal("%s carries no %s/%s -- the BSP layout changed"
                 % (archive, tree, d.getVar('QNX_PROCESSOR')))

    bb.note("%s: unpacked %d files from %s"
            % (d.getVar('PN'), extracted, os.path.basename(archive)))
}

do_install() {
	install -d ${D}${QNX_STAGE_DIR}
	cp -a ${S}/${QNX_BSP_TREE}/${QNX_PROCESSOR} ${D}${QNX_STAGE_DIR}/

	for path in ${QNX_BSP_EXCLUDE}; do
		rm -f "${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR}/$path"
	done

	# An empty usr/lib after the pruning is still a directory two recipes both
	# create, which Yocto does not mind -- but leaving one behind for no reason
	# is untidy, so drop any that emptied.
	find ${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR} -type d -empty -delete
}


def qnx_bsp_pattern(d):
    """The archive glob, with the recipe's own value guaranteed to be present.

    Both callers go through here so that "the recipe never set the glob" is one
    named error rather than two different ones -- a fatal from the guard below,
    or an IsADirectoryError from the middle of do_unpack."""
    import os

    zipglob = (d.getVar('QNX_BSP_ZIP_GLOB') or '').strip()
    if not zipglob:
        bb.fatal("%s inherits qnx-bsp but sets no QNX_BSP_ZIP_GLOB, so there is "
                 "no archive name to look for. Set it to the BSP zip's name "
                 "with the release digits globbed, e.g. \"BSP_hyp-guest-arm_*.zip\"."
                 % d.getVar('PN'))

    return os.path.join(d.getVar('QNX_BSP_ZIP_DIR') or '', zipglob)


# An SDP without the BSP package is a legitimate state -- an older install, or a
# build that points at a BSP tree of its own and never needs this recipe. Skip
# with something actionable rather than failing whatever asked for it with a
# glob that matched nothing.
#
# Only files count. A glob that matched the bsp directory itself is how an unset
# QNX_BSP_ZIP_GLOB used to get past this guard and fail later, in do_unpack,
# with an error naming neither the recipe nor the variable.
python () {
    import glob
    import os

    pattern = qnx_bsp_pattern(d)
    if not [p for p in glob.glob(pattern) if os.path.isfile(p)]:
        raise bb.parse.SkipRecipe(
            "no BSP archive matching %s. It comes from the SDP package %s: name "
            "it in QNX_SDP_FEATURES or QNX_SDP_EXTRA_PACKAGES and run "
            "'bitbake -c install_sdp qnx-sdp'."
            % (pattern, d.getVar('QNX_SDP_REQUIRES') or '(unset)'))
}
