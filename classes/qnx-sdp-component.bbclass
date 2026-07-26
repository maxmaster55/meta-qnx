# qnx-sdp-component.bbclass -- give a prebuilt part of the SDP a name.
#
# The SDP is not built here and its files are already on disk, so a recipe that
# copied them into the stage tree would add a hop without adding capability:
# mkifs already searches ${QNX_TARGET}, and staging mods-phy.so would only let
# an image name it somewhere else. This class therefore installs nothing. What
# it produces is the .files drop-in -- records whose sources are bare names that
# mkifs resolves for itself.
#
# The reason to want that is not tidiness. A component like pci-server is one
# binary, ~30 dlopen'd modules and two config files, and taking three of the
# thirty gives a pci-server that starts, finds no way to enumerate a bus and
# exits before creating /dev/pci -- after which every driver behind it fails in
# a way that mentions anything but PCI. A .build fragment is a flat list and
# cannot say "these thirty-three things are one component, all or nothing".
# A recipe can, and then:
#
#     QNX_IFS_INSTALL += "qnx-pci-server"
#
# is the whole of what an image has to know, a second image gets it right by
# construction, and the "did I list all thirty?" question is asked once.
#
# A component is an ordinary recipe that builds nothing:
#
#     SUMMARY = "PCI server and its modules"
#     LICENSE = "CLOSED"
#     inherit qnx-sdp-component
#     QNX_COMPONENT_FILES = "pci-server pci-connector libpci.so \
#                            pci/pci_server-namespace.so ..."
#
# Startup commands, ordering and waitfor come from qnx-image-contract unchanged
# (QNX_IFS_STARTUP_CMD, QNX_IFS_STARTUP_AFTER, QNX_IFS_STARTUP_WAITFOR), so a
# component that has to be launched says so the same way an application does.

inherit qnx-image-contract

# ---------------------------------------------------------------------------
# What the component consists of
# ---------------------------------------------------------------------------
# Whitespace-separated source names, each resolved against QNX_COMPONENT_ROOTS
# the way mkifs would. A name may carry a subdirectory (pci/pci_debug2.so) for
# the nested module directories, which mkifs's search path does not descend into.
#
# The destination is derived from where the file was found: something under
# <root>/${QNX_PROCESSOR}/usr/lib lands at /usr/lib. That is the layout every
# image's LD_LIBRARY_PATH and PATH already expect, and it means a component
# never has to state a destination it would only get wrong.
QNX_COMPONENT_FILES ?= ""

# Names that may legitimately be absent -- an SDP installed without an optional
# package, a driver only some boards have. Missing ones are dropped with a note
# instead of failing the build.
QNX_COMPONENT_OPTIONAL ?= ""

# Destination overrides, keyed by the source name exactly as written in
# QNX_COMPONENT_FILES. For the handful of files whose image path is not where
# the SDP keeps them -- the dynamic loader being the standing example, which
# lives in usr/lib but has to be at /proc/boot.
QNX_COMPONENT_DEST[dummy] ?= ""

# Extra mkifs attributes, same keying.
QNX_COMPONENT_ATTR[dummy] ?= ""

# Varflags are invisible to task signatures, so serialise them into variables
# that are not. Without this, changing a destination would not rebuild.
QNX_COMPONENT_DEST_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_COMPONENT_DEST')}"
QNX_COMPONENT_ATTR_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_COMPONENT_ATTR')}"

# Declared here as well as in qnx-sdp and qnx-toolchain, and that duplication is
# deliberate. A component inherits neither: it compiles nothing, so it wants
# none of qnx-sdp's toolchain surgery. Without this line QNX_TARGET is defined
# only when one of those classes happens to be in the build -- and
# `INHERIT += "qnx-toolchain"` is commented out in the shipped local.conf, so in
# a default build every component would resolve its files against an empty path
# and quietly contribute nothing. QNX_SDP_ROOT comes from layer.conf and
# QNX_PROCESSOR from the machine conf, so those are always present.
QNX_TARGET ?= "${QNX_SDP_ROOT}/target/qnx"

# Where to look. The SDP by default; a board layer prepends its BSP install tree
# for drivers the SDP does not ship (devb-sdmmc-bcm2712 and friends). Searched
# left to right, so a BSP build of a name the SDP also has wins -- the same
# precedence mkifs applies to its own -r roots.
QNX_COMPONENT_ROOTS ?= "${QNX_TARGET}"

# The subdirectories searched under each root, and equally the image paths a
# resolved file maps onto. Matches QNX_IFS_SEARCH_SUBDIRS in qnx-ifs.bbclass.
QNX_COMPONENT_SUBDIRS ?= "lib lib/dll usr/lib bin sbin usr/bin usr/sbin usr/libexec boot/sys"

# Nothing is installed, so there is nothing to harvest and no ELF to check --
# the files stay in the SDP and mkifs reads them from there.
QNX_IFS_AUTO_ENTRIES = "0"
QNX_ELF_CHECK = "0"

# The drop-in still has to reach the image, and it lives in the stage tree.
SYSROOT_DIRS += "${QNX_STAGE_DIR}"

# Same reasoning as qnx-packagegroup: produces no Linux package, should not be
# attempted by `bitbake world`, and only means anything for a QNX machine.
inherit nopackages
INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"
COMPATIBLE_MACHINE = "qnx-aarch64le"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Nothing is configured or compiled -- the files are prebuilt and stay where
# they are. Fetch, unpack and patch are deliberately left alone: they cost
# nothing with an empty SRC_URI, and a component may legitimately carry a file
# of its own (a config file, a helper script) that has no SDP equivalent. Making
# them noexec here would silently leave that file unpacked, and do_install would
# fail on a path that exists in the recipe and not on disk.
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[dirs] = "${D}"

# A component is nothing but names of SDP files, so without an SDP there is
# nothing it can describe. Skipping matches what qnx-sdp.bbclass does for
# recipes that compile against one, and keeps "no SDP yet" a single actionable
# message rather than one failure per component.
python () {
    import os
    target = d.getVar('QNX_TARGET') or ''
    if not os.path.isdir(target):
        raise bb.parse.SkipRecipe(
            "no SDP at '%s'. Point QNX_SDP_ROOT at an existing install, or run "
            "'bitbake -c install_sdp qnx-sdp' to create one." % target)
}


def qnx_component_search_dirs(d):
    """(host directory, image directory) pairs, in mkifs's own order."""
    import os

    processor = d.getVar('QNX_PROCESSOR')
    subdirs = (d.getVar('QNX_COMPONENT_SUBDIRS') or '').split()
    roots = (d.getVar('QNX_COMPONENT_ROOTS') or '').split()

    return [(os.path.join(root, processor, sub), '/' + sub)
            for root in roots for sub in subdirs]


def qnx_component_records(d):
    """QNX_COMPONENT_FILES as mkifs records, resolved against the SDP.

    Returned as a string rather than written to the drop-in directly, and fed
    into QNX_IFS_EXTRA_ENTRIES so that qnx-image-contract's own writer emits
    them. That is not indirection for its own sake: qnx-toolchain is applied
    through a global INHERIT and adds qnx_image_write_dropins to do_install's
    postfuncs itself, so the writer runs more than once and any file this class
    wrote on its own would be overwritten by the later run. Going through the
    variable makes every run produce the same thing."""
    import os

    pn = d.getVar('PN')
    names = (d.getVar('QNX_COMPONENT_FILES') or '').split()
    if not names:
        return ''

    # No SDP at all is not this class's error to report. qnx-sdp.bbclass already
    # raises SkipRecipe with a message that says what to do about it, and the
    # guard below does the same for components -- but this function is called
    # during variable expansion, which happens whether or not a recipe is going
    # to be skipped. Failing here would turn "you have not installed an SDP yet"
    # into a parse error from every component at once, burying the one message
    # that is worth reading.
    if not os.path.isdir(d.getVar('QNX_TARGET') or ''):
        return ''

    search_dirs = qnx_component_search_dirs(d)
    optional = set((d.getVar('QNX_COMPONENT_OPTIONAL') or '').split())
    dest_map = qnx_ifs_flags(d, 'QNX_COMPONENT_DEST')
    attr_map = qnx_ifs_flags(d, 'QNX_COMPONENT_ATTR')

    records = []
    missing = []

    for name in names:
        found = None
        for host_dir, image_dir in search_dirs:
            candidate = os.path.join(host_dir, name)
            if os.path.exists(candidate):
                found = image_dir
                break

        if found is None:
            # Resolving here rather than leaving it to mkifs is most of the
            # point of the class: the build stops, naming the component and the
            # file, instead of the board reporting a driver that "could not
            # start" for reasons that mention neither.
            if name in optional:
                bb.note("%s: optional %s is not in the SDP; skipping" % (pn, name))
            else:
                missing.append(name)
            continue

        dest = dest_map.get(name, '').strip() or '%s/%s' % (found, name)
        attr = attr_map.get(name, '').strip()
        prefix = '[%s] ' % attr if attr else ''
        records.append('%s%s=%s' % (prefix, dest, name))

    if missing:
        bb.fatal("%s: not found under %s:\n  %s\n"
                 "These are SDP or BSP files this component is made of. Either "
                 "the SDP lacks the package that provides them (see "
                 "QNX_SDP_FEATURES), or the name is wrong. List them in "
                 "QNX_COMPONENT_OPTIONAL if they are genuinely optional."
                 % (pn, ' '.join((d.getVar('QNX_COMPONENT_ROOTS') or '').split()),
                    '\n  '.join(missing)))

    return '\n'.join(records)


# Prepended, so a component's own QNX_IFS_EXTRA_ENTRIES -- inline config files,
# links, anything with no SDP file behind it -- follows its file list.
QNX_IFS_EXTRA_ENTRIES:prepend = "${@qnx_component_records(d)}\n"

# The writer itself. Added here rather than relied upon from qnx-toolchain, so a
# component still produces its drop-in in a build that does not inherit it.
# Running twice is harmless now that the records travel in a variable.
do_install[postfuncs] += "qnx_image_write_dropins"
