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

SYSROOT_DIRS += "${QNX_STAGE_DIR}"

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
