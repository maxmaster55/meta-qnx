# qnx-sdp.bbclass -- build a recipe with the QNX SDP toolchain instead of Yocto's.
#
# Yocto cannot build QNX the way it builds Linux: there is no QNX TCLIBC, no
# TARGET_OS=nto, no procnto recipe and no do_rootfs. Everything QNX comes as
# prebuilt binaries from an SDP installed by qnxsoftwarecenter_clt.
#
# So this class uses bitbake purely as a task engine and dependency graph on top
# of an existing SDP:
#   - CC/CXX/... are replaced with qcc/q++ from $QNX_HOST
#   - Yocto's own cross-toolchain is never pulled in (INHIBIT_DEFAULT_DEPS)
#   - packaging is switched off entirely (nopackages), since .ipk/.rpm of QNX
#     ELFs is meaningless and package QA would reject them as foreign binaries
#
# Note that TARGET_OS stays "linux" in bitbake's metadata. That is cosmetic:
# nothing here invokes Yocto's cross-gcc, sysroot or packaging, so the triplet
# is never used. Making bitbake believe in aarch64-unknown-nto-qnx8.0.0 would
# mean patching siteinfo.bbclass and inventing a TCLIBC, for no gain.
#
# The SDP is treated as strictly READ-ONLY. Nothing in this layer writes to it.

# ---------------------------------------------------------------------------
# SDP location
# ---------------------------------------------------------------------------
# Set QNX_SDP_ROOT in local.conf (or site.conf) to your SDP install. There is no
# sensible default, so fail early and by name rather than with a confusing
# "qcc: command not found" halfway through do_compile.
QNX_SDP_ROOT ??= ""

python () {
    sdp = d.getVar('QNX_SDP_ROOT')
    if not sdp:
        raise bb.parse.SkipRecipe(
            "QNX_SDP_ROOT is not set. Point it at a QNX SDP install in local.conf, "
            "e.g. QNX_SDP_ROOT = \"/path/to/qnx800\"")
    if not os.path.isdir(os.path.join(sdp, 'target', 'qnx')):
        raise bb.parse.SkipRecipe(
            "QNX_SDP_ROOT '%s' does not look like a QNX SDP (no target/qnx)" % sdp)
}

QNX_HOST ?= "${QNX_SDP_ROOT}/host/linux/x86_64"
QNX_TARGET ?= "${QNX_SDP_ROOT}/target/qnx"

# qcc reads its target definitions from $QNX_CONFIGURATION (qconfig/, license/).
# qnxsdp-env.sh points this at $HOME/.qnx; bitbake does pass HOME through, but
# pin it explicitly so the build does not depend on the caller's environment.
QNX_CONFIGURATION ?= "${@os.path.join(os.environ.get('HOME', '/root'), '.qnx')}"
QNX_CONFIGURATION_EXCLUSIVE ?= "${QNX_CONFIGURATION}"

export QNX_HOST
export QNX_TARGET
export QNX_CONFIGURATION
export QNX_CONFIGURATION_EXCLUSIVE

# qcc, q++, mkifs, mkqnx6fsimg, diskimage, dumpifs all live here. host/common/bin
# carries the rest of the SDP host tooling.
PATH:prepend = "${QNX_HOST}/usr/bin:${QNX_SDP_ROOT}/host/common/bin:"

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------
# Verified: qcc needs nothing but QNX_HOST/QNX_TARGET/PATH -- sourcing
# qnxsdp-env.sh is not required, which is what makes this class possible.
QNX_VARIANT ?= "gcc_ntoaarch64le"
QNX_TOOL_PREFIX ?= "aarch64-unknown-nto-qnx8.0.0-"

CC = "qcc -V${QNX_VARIANT}"
CXX = "q++ -V${QNX_VARIANT}"
CPP = "qcc -V${QNX_VARIANT} -E"
LD = "qcc -V${QNX_VARIANT}"
AR = "${QNX_TOOL_PREFIX}ar"
NM = "${QNX_TOOL_PREFIX}nm"
RANLIB = "${QNX_TOOL_PREFIX}ranlib"
STRIP = "${QNX_TOOL_PREFIX}strip"
OBJCOPY = "${QNX_TOOL_PREFIX}objcopy"
OBJDUMP = "${QNX_TOOL_PREFIX}objdump"
READELF = "${QNX_TOOL_PREFIX}readelf"

# Yocto's default flags carry --sysroot=, -fmacro-prefix-map, and a pile of
# hardening options aimed at its own gcc. qcc rejects several of them outright,
# and the sysroot would point at a Linux sysroot that must never be used here.
TARGET_CC_ARCH = ""
TARGET_LD_ARCH = ""
TARGET_CPPFLAGS = ""
TOOLCHAIN_OPTIONS = ""
DEBUG_PREFIX_MAP = ""
SECURITY_CFLAGS = ""
SECURITY_LDFLAGS = ""
LDFLAGS = ""

CFLAGS = "-O2 -Wall -Wextra"
CXXFLAGS = "-O2 -Wall -Wextra"

# ---------------------------------------------------------------------------
# Disable the Linux-oriented machinery
# ---------------------------------------------------------------------------
# No cross-gcc / libc / gettext dependency -- we bring our own compiler.
INHIBIT_DEFAULT_DEPS = "1"

# No do_package/do_package_write_* and therefore no package QA on QNX ELFs.
inherit nopackages

# `bitbake world` would try these against every machine; they only make sense
# for a QNX machine and are built by name.
EXCLUDE_FROM_WORLD = "1"
COMPATIBLE_MACHINE = "qnx-aarch64le"

# ---------------------------------------------------------------------------
# Staging contract
# ---------------------------------------------------------------------------
# Recipes install target files under ${D}${QNX_STAGE_DIR}, laid out to mirror
# $QNX_TARGET: ${QNX_STAGE_DIR}/aarch64le/{bin,sbin,lib}/...
#
# That layout is not arbitrary -- it is exactly what `mkifs -r <root>` expects,
# and it matches the existing hand-built install/ trees in the QNX hypervisor
# repo (qnx_host/install/aarch64le/sbin/..., qnx_guests/install/aarch64le/...).
# Keeping the convention means existing .build files stay reusable verbatim.
#
# SYSROOT_DIRS makes the tree flow into a dependent recipe's RECIPE_SYSROOT via
# a plain DEPENDS, which is what replaces the hand-rolled .build dependency
# scraping in the makefile-based build.
QNX_STAGE_DIR = "/qnx-stage"
QNX_STAGE_BINDIR = "${QNX_STAGE_DIR}/${QNX_PROCESSOR}/bin"
QNX_STAGE_SBINDIR = "${QNX_STAGE_DIR}/${QNX_PROCESSOR}/sbin"
QNX_STAGE_LIBDIR = "${QNX_STAGE_DIR}/${QNX_PROCESSOR}/lib"
QNX_STAGE_USRLIBDIR = "${QNX_STAGE_DIR}/${QNX_PROCESSOR}/usr/lib"
QNX_STAGE_INCLUDEDIR = "${QNX_STAGE_DIR}/usr/include"

SYSROOT_DIRS += "${QNX_STAGE_DIR}"

# ---------------------------------------------------------------------------
# The stage tree is also the sysroot
# ---------------------------------------------------------------------------
# One tree serves both roles, because $QNX_TARGET's layout happens to suit both:
# `mkifs -r` wants ${PROCESSOR}/{bin,sbin,lib}, and a compiler wants
# usr/include + ${PROCESSOR}/lib. The QNX hypervisor project's hand-built trees
# already work this way -- qnx_guests/install/ holds usr/include/ and
# aarch64le/sbin/ side by side -- so there is nothing to invent and existing
# install rules keep working. rpi-gpio's CMakeLists, for instance, already
# installs to ${CMAKE_SYSTEM_PROCESSOR}/sbin and usr/include/sys.
#
# This is what turns "app B needs app A's library and headers" into a plain
# DEPENDS, which is the thing the makefile build cannot express: see the
# ORDERED_DIRS comment in src/Makefile, where someip has to be built before
# motor_ai_* by hand because they link against libraries it produces.
QNX_SYSROOT_CPPFLAGS ?= "-I${RECIPE_SYSROOT}${QNX_STAGE_INCLUDEDIR}"
QNX_SYSROOT_LDFLAGS ?= "-L${RECIPE_SYSROOT}${QNX_STAGE_LIBDIR} \
                        -L${RECIPE_SYSROOT}${QNX_STAGE_USRLIBDIR}"

CFLAGS:append = " ${QNX_SYSROOT_CPPFLAGS}"
CXXFLAGS:append = " ${QNX_SYSROOT_CPPFLAGS}"
LDFLAGS:append = " ${QNX_SYSROOT_LDFLAGS}"

# RECIPE_SYSROOT is a per-recipe absolute path; including it verbatim in the
# task hash would make every recipe's signature depend on its own build
# location. OE excludes it from the standard flags for the same reason.
CFLAGS[vardepsexclude] += "QNX_SYSROOT_CPPFLAGS"
CXXFLAGS[vardepsexclude] += "QNX_SYSROOT_CPPFLAGS"
LDFLAGS[vardepsexclude] += "QNX_SYSROOT_LDFLAGS"

# The staged files are QNX aarch64 ELFs. Yocto's aarch64-poky-linux-strip has no
# business touching them.
INHIBIT_SYSROOT_STRIP = "1"

# ...and without this, INHIBIT_SYSROOT_STRIP is not enough. staging.bbclass makes
# every class-target recipe's do_populate_sysroot depend on
# virtual/${HOST_PREFIX}binutils (POPULATESYSROOTDEPS) so that it *can* strip.
# That single dependency drags in binutils-cross and, through it, Yocto's entire
# cross toolchain: ~190 tasks and a large source download, none of which is ever
# used to build anything here. Clearing it is the difference between a build that
# needs the network for half an hour and one that needs neither.
#
# Note the :class-target override: staging.bbclass sets POPULATESYSROOTDEPS both
# unconditionally and per-class, and our recipes are class-target, so clearing
# only the plain variable leaves the override in force.
POPULATESYSROOTDEPS = ""
POPULATESYSROOTDEPS:class-target = ""
POPULATESYSROOTDEPS:class-nativesdk = ""
INHIBIT_PACKAGE_STRIP = "1"

# ---------------------------------------------------------------------------
# IFS drop-ins -- how a recipe gets itself into an image
# ---------------------------------------------------------------------------
# An image should never have to be edited to gain an application. On Linux you
# add a package to IMAGE_INSTALL and its files appear; here the equivalent is
# QNX_IFS_INSTALL (see qnx-ifs.bbclass), and this is the half that makes it work.
#
# Every recipe drops a fragment of mkifs syntax into the stage tree describing
# what it contributes to an image:
#
#   ${QNX_IFS_DROPIN_DIR}/${PN}.files     mkifs entries (one per staged file)
#   ${QNX_IFS_DROPIN_DIR}/${PN}.startup   lines for the boot script, if any
#
# The image recipe concatenates the fragments of everything it installs into a
# generated .build file. Same idea as an /etc/something.d directory: the app owns
# its own entry, and the thing consuming it never enumerates its members.
#
# By default the .files fragment is derived automatically from whatever the
# recipe installed, so a normal application recipe declares nothing at all.
QNX_IFS_DROPIN_DIR = "${QNX_STAGE_DIR}/ifs.d"

# Set to "0" in a recipe that wants to spell out its entries by hand.
QNX_IFS_AUTO_ENTRIES ?= "1"

# Command(s) to run from the image's startup script, e.g. "my-daemon &".
QNX_IFS_STARTUP_CMD ?= ""

# Raw mkifs lines for anything the automatic pass cannot express: permissions,
# uid/gid, symlinks, inline config files, [search=...] for unusual locations.
QNX_IFS_EXTRA_ENTRIES ?= ""

# mkifs resolves a bare source name against its search path, which `-r <root>`
# re-roots onto our stage tree. Only these directories are on that path, so only
# files installed into them can be referenced by bare name.
QNX_IFS_SEARCHABLE_DIRS ?= "bin sbin lib usr/bin usr/sbin usr/lib lib/dll boot/sys"

# Staged content that belongs to the sysroot rather than to any image. Headers
# and static libraries are build inputs for other recipes; putting them in an
# IFS would only waste RAM. Excluded silently -- unlike an unexpected location,
# this is not a mistake worth warning about.
QNX_IFS_EXCLUDE_DIRS ?= "usr/include include"
QNX_IFS_EXCLUDE_SUFFIXES ?= ".a .la .pc .h .hpp"

python qnx_sdp_write_ifs_dropin() {
    import os

    destdir = d.getVar('D')
    proc = d.getVar('QNX_PROCESSOR')
    stage_root = os.path.join(destdir + d.getVar('QNX_STAGE_DIR'), proc)
    pn = d.getVar('PN')

    entries = []

    if d.getVar('QNX_IFS_AUTO_ENTRIES') == '1' and os.path.isdir(stage_root):
        searchable = (d.getVar('QNX_IFS_SEARCHABLE_DIRS') or '').split()
        excluded = (d.getVar('QNX_IFS_EXCLUDE_DIRS') or '').split()
        excl_suffix = tuple((d.getVar('QNX_IFS_EXCLUDE_SUFFIXES') or '').split())

        for dirpath, _, filenames in os.walk(stage_root):
            reldir = os.path.relpath(dirpath, stage_root)
            reldir = '' if reldir == '.' else reldir

            # Build inputs for other recipes, not image content.
            if any(reldir == x or reldir.startswith(x + '/') for x in excluded):
                continue

            for name in sorted(filenames):
                if name.endswith(excl_suffix):
                    continue

                ifs_dest = '/%s/%s' % (reldir, name)
                full = os.path.join(dirpath, name)

                if os.path.islink(full):
                    # Versioned shared libraries stage as a chain --
                    # libfoo.so -> libfoo.so.1 -> libfoo.so.1.2.3. Emitting a
                    # symlink as a plain entry would silently duplicate the
                    # payload once per name.
                    entries.append('[type=link] %s=%s'
                                   % (ifs_dest, os.readlink(full)))
                elif reldir in searchable:
                    # e.g. aarch64le/bin/qnx-hello  ->  /bin/qnx-hello=qnx-hello
                    entries.append('%s=%s' % (ifs_dest, name))
                else:
                    bb.warn("%s: %s/%s is outside the mkifs search path (%s). "
                            "It will not be added to images automatically; add an "
                            "explicit entry via QNX_IFS_EXTRA_ENTRIES."
                            % (pn, reldir or '.', name, ' '.join(searchable)))

    extra = (d.getVar('QNX_IFS_EXTRA_ENTRIES') or '').strip()

    if entries or extra:
        dropin_dir = destdir + d.getVar('QNX_IFS_DROPIN_DIR')
        bb.utils.mkdirhier(dropin_dir)
        with open(os.path.join(dropin_dir, pn + '.files'), 'w') as f:
            f.write('### %s\n' % pn)
            for e in entries:
                f.write(e + '\n')
            if extra:
                f.write(extra + '\n')

    startup = (d.getVar('QNX_IFS_STARTUP_CMD') or '').strip()
    if startup:
        dropin_dir = destdir + d.getVar('QNX_IFS_DROPIN_DIR')
        bb.utils.mkdirhier(dropin_dir)
        with open(os.path.join(dropin_dir, pn + '.startup'), 'w') as f:
            f.write('### %s\n' % pn)
            f.write(startup + '\n')
}
do_install[postfuncs] += "qnx_sdp_write_ifs_dropin"

# Without these, editing QNX_IFS_STARTUP_CMD or QNX_IFS_EXTRA_ENTRIES would not
# invalidate do_install, and the change would silently not reach the image.
qnx_sdp_write_ifs_dropin[vardeps] += "QNX_IFS_AUTO_ENTRIES QNX_IFS_STARTUP_CMD \
                                      QNX_IFS_EXTRA_ENTRIES QNX_IFS_SEARCHABLE_DIRS"
