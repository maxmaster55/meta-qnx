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
#
# How a recipe gets itself into an image is NOT here: that is the drop-in
# contract in qnx-image-contract.bbclass, which stock recipes built by
# qnx-toolchain.bbclass use as well. All this class adds to it is the layout
# those drop-ins are harvested from -- the stage tree, described below.

inherit qnx-image-contract

# ---------------------------------------------------------------------------
# SDP location
# ---------------------------------------------------------------------------
# QNX_SDP_ROOT defaults to ${TOPDIR}/qnx-sdp in conf/layer.conf, like DL_DIR;
# set it in local.conf to use an SDP you already have. Recipes are skipped with
# an explanation when it does not point at one, rather than failing later with a
# confusing "qcc: command not found" in the middle of do_compile.
python () {
    sdp = d.getVar('QNX_SDP_ROOT')
    if not sdp:
        raise bb.parse.SkipRecipe(
            "QNX_SDP_ROOT is empty. Set it in local.conf, e.g.\n"
            '  QNX_SDP_ROOT = "/path/to/qnx800"')
    if not os.path.isdir(os.path.join(sdp, 'target', 'qnx')):
        raise bb.parse.SkipRecipe(
            "QNX_SDP_ROOT '%s' is not a QNX SDP (no target/qnx). Either point it "
            "at an existing install in local.conf, or run "
            "'bitbake -c install_sdp qnx-sdp' to create one there." % sdp)
}

QNX_HOST ?= "${QNX_SDP_ROOT}/host/linux/x86_64"
QNX_TARGET ?= "${QNX_SDP_ROOT}/target/qnx"

# qcc reads its target definitions from $QNX_CONFIGURATION (qconfig/, license/).
# qnxsdp-env.sh points this at $HOME/.qnx; bitbake does pass HOME through, but
# pin it explicitly so the build does not depend on the caller's environment.
# ${HOME} rather than os.environ: bitbake already carries the invoking user's
# home in the datastore, and it is correct per task. Reading os.environ here
# instead evaluates in whichever bitbake process parses the class -- which set
# HOME=/root and produced "You don't have a valid license for this product",
# because the SDP looked for its licence under the wrong home.
QNX_CONFIGURATION ?= "${HOME}/.qnx"
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
# Getting into an image
# ---------------------------------------------------------------------------
# The drop-in contract itself (QNX_IFS_STARTUP_CMD, QNX_IFS_ATTR, the .files and
# .startup fragments and the harvester that writes them) lives in
# qnx-image-contract.bbclass, inherited above, because a stock recipe built by
# qnx-toolchain.bbclass uses exactly the same contract.
#
# All that is specific to a qnx-sdp recipe is *where* its files are and how an
# entry names them. Our recipes install into the stage tree, whose layout is
# already what `mkifs -r <root>` expects, so an entry can name its source by
# bare name and let mkifs resolve it -- the same form the project's hand-written
# .build files use, which is what keeps those files reusable verbatim.
QNX_IMAGE_HARVEST_DIRS = "${QNX_STAGE_DIR}/${QNX_PROCESSOR}"
QNX_IMAGE_SOURCE_STYLE = "search"

# The ELF check covers the whole stage tree, not just the harvested part: a
# foreign binary under usr/include or in a subdirectory outside the search path
# is just as wrong, and is exactly the case the check exists to catch.
QNX_ELF_CHECK_DIRS = "${QNX_STAGE_DIR}"

do_install[postfuncs] += "qnx_image_write_dropins qnx_image_check_elfs"

# ---------------------------------------------------------------------------
# dumpbuild -- see the build file that was generated
# ---------------------------------------------------------------------------
# `bitbake -c dumpbuild <image>` prints the generated .build file on the
# console, generating it first if needed.
#
# The counterpart to dumpifs. dumpifs answers "what ended up in the image";
# this answers "what did we ask for", which is the question when something is
# missing -- an entry the automatic dependency pass never added, a marker that
# expanded to the wrong path, a fragment that was not included. Those are
# invisible in the finished image and obvious here.
#
# The file is also deployed beside the image, so this is a convenience rather
# than the only way to read it. It saves knowing which of ${B} or the deploy
# directory to look in, and what the file is called for this particular recipe.
#
# Set by whichever class generates one. Space separated, because the disk
# produces two.
#
# The function lives here but the task does not: qnx-ifs, qnx-rootfs and
# qnx-disk each `addtask dumpbuild` after their own generating task, since that
# is the only ordering that makes sense per class. A plain qnx-sdp recipe
# therefore has no dumpbuild at all, and bitbake says so better than this could
# ("Task do_dumpbuild does not exist for target x. Close matches: do_build").
# The guard below is for an image recipe that deliberately empties this.
QNX_BUILDFILES ?= ""

python do_dumpbuild() {
    import os

    files = (d.getVar('QNX_BUILDFILES') or '').split()
    if not files:
        bb.fatal("%s generates no build file. dumpbuild works on recipes that "
                 "inherit qnx-ifs, qnx-rootfs or qnx-disk."
                 % d.getVar('PN'))

    missing = []
    for path in files:
        if not os.path.isfile(path):
            missing.append(path)
            continue
        # bb.plain rather than a shell task: a shell task's stdout only reaches
        # the log file, and the point of this is to appear on the console.
        bb.plain("### %s\n%s" % (path, open(path).read()))

    # Only fatal when nothing at all was printed. The disk names two files and
    # the second is written by a later task, so a partial result is normal and
    # still worth showing.
    if len(missing) == len(files):
        bb.fatal("none of the expected build files exist: %s -- did the "
                 "generating task run?" % ' '.join(missing))
    for path in missing:
        bb.warn("%s does not exist yet" % path)
}
do_dumpbuild[nostamp] = "1"
do_dumpbuild[doc] = "Print the generated build file"


# ---------------------------------------------------------------------------
# Template includes
# ---------------------------------------------------------------------------
# Directories searched for `#include` fragments in a .build template, in order.
# Each layer appends its own in conf/layer.conf, so a board layer can share a
# fragment with an image layer without either knowing the other's path.
#
# This is what stops a host and a guest image from being two copies of the same
# 200-line build file: the parts that genuinely are the same -- the boot header,
# the startup preamble, the base utilities -- live in one fragment that both
# include, and each image keeps only what is actually different about it.
QNX_TEMPLATE_INCLUDE_PATH ?= ""


def qnx_template_includes(d):
    """Every fragment on the include path, sorted.

    Used for do_*_buildfile[file-checksums], so editing a fragment rebuilds the
    images that use it. Deliberately the whole path rather than the fragments a
    given template actually pulls in: which ones those are is only known once
    the task runs, and file-checksums has to be set at parse time. The cost of
    the over-approximation is that editing an unused fragment rebuilds an image
    that did not need it, which is cheap and safe in the direction that matters.
    """
    import os

    found = []
    for directory in (d.getVar('QNX_TEMPLATE_INCLUDE_PATH') or '').split():
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isfile(path):
                found.append(path)
    return sorted(found)


def qnx_template_include_checksums(d):
    return ' '.join('%s:True' % p for p in qnx_template_includes(d))


def qnx_read_template(d, template, _trail=None):
    """Read a template, resolving `#include` lines recursively.

    A fragment is included by name:

        #include qnx-base.build.inc

    resolved against the including file's own directory first, then
    QNX_TEMPLATE_INCLUDE_PATH. Angle brackets or quotes around the name are
    accepted and ignored, so the C-ish spelling reads naturally.

    The `#` is not an accident: mkifs treats the line as a comment, so a
    template with includes in it is still a syntactically valid build file, and
    the ones that never include anything are unaffected."""
    import os
    import re

    if not os.path.isfile(template):
        bb.fatal("template not found: %s" % template)

    trail = _trail or ()
    real = os.path.realpath(template)
    if real in trail:
        bb.fatal("template include cycle: %s"
                 % ' -> '.join([os.path.basename(p) for p in trail] +
                               [os.path.basename(real)]))

    search = [os.path.dirname(real)]
    search += (d.getVar('QNX_TEMPLATE_INCLUDE_PATH') or '').split()

    out = []
    with open(template) as f:
        for lineno, line in enumerate(f, 1):
            match = re.match(r'\s*#include\s+[<"]?([^>"\s]+)[>"]?\s*$', line)
            if not match:
                out.append(line)
                continue

            name = match.group(1)
            for directory in search:
                candidate = os.path.join(directory, name)
                if os.path.isfile(candidate):
                    break
            else:
                bb.fatal("%s:%d: cannot find included fragment '%s'. Searched:"
                         "\n  %s\nAdd its directory to QNX_TEMPLATE_INCLUDE_PATH "
                         "in the providing layer's conf/layer.conf."
                         % (template, lineno, name, '\n  '.join(search)))

            out.append('### >>> %s\n' % name)
            out.append(qnx_read_template(d, candidate, trail + (real,)))
            out.append('### <<< %s\n' % name)

    return ''.join(out)


def qnx_expand_template(d, template, generated=None):
    """Expand @VARIABLE@ markers in a template against the datastore.

    Shared by the IFS and disk-image classes. bitbake's own ${...} syntax is
    deliberately not used: QNX build files use ${...} for their own variables
    (${PROCESSOR}, ${QNX_TARGET}), and expanding those would corrupt them.

    `#include` lines are resolved first, so a fragment may carry @VARIABLE@
    markers of its own and they expand in the including image's context -- which
    is the point of sharing one.

    `generated` supplies values computed at task time, which take precedence."""
    import re
    import os

    generated = generated or {}

    content = qnx_read_template(d, template)

    def expand(match):
        name = match.group(1)
        if name in generated:
            return generated[name]
        value = d.getVar(name)
        if value is None:
            bb.fatal("%s references @%s@, which is not set" % (template, name))
        return value

    # Two or more characters, matching the fragment expander in qnx-ifs.bbclass
    # and for the same reason: @S@ is QNX's crypt-format delimiter in
    # /etc/shadow, not a marker, and expanding it corrupts every password hash
    # in the image without producing a single warning.
    return re.sub(r'@([A-Z][A-Z0-9_]+)@', expand, content)


def qnx_parse_size(text, what='size'):
    """Accept 1234, 16K, 200M, 2G (also KiB-style suffixes) and return bytes."""
    text = (text or '').strip()
    units = {'': 1, 'K': 1024, 'M': 1024 ** 2, 'G': 1024 ** 3, 'T': 1024 ** 4}
    suffix = text[-1:].upper()
    if suffix in units and suffix != '':
        number, factor = text[:-1], units[suffix]
    else:
        number, factor = text, 1
    try:
        return int(float(number) * factor)
    except ValueError:
        bb.fatal("cannot parse %s '%s' -- expected a number with an optional "
                 "K/M/G suffix, or 'auto'" % (what, text))


def qnx_sdp_task_env(d):
    """The SDP environment a python task's subprocess needs.

    A python task inherits bitbake's own environment, not the one bitbake
    generates for shell tasks, so the SDP variables and HOME that `export` puts
    in a shell task are simply absent. Without them the licence check looks for
    its lock file under the wrong home and reports a misleading error. Every
    python task that shells out to an SDP tool builds its environment from here."""
    import os
    env = dict(os.environ)
    for var in ('HOME', 'QNX_HOST', 'QNX_TARGET', 'QNX_CONFIGURATION',
                'QNX_CONFIGURATION_EXCLUSIVE', 'PATH', 'PROCESSOR', 'ARCH'):
        value = d.getVar(var)
        if value:
            env[var] = value
    return env


def qnx_build_fsimg(d, tool, buildfile, out, auto, env, attempts=6, factor=1.5, cwd=None):
    """Run a QNX filesystem-image tool, growing the image until it fits.

    Shared by qnx-disk (boot partition via mkfatfsimg) and qnx-rootfs (any
    QNX6 filesystem via mkqnx6fsimg), because building a filesystem image is
    one operation whichever image wants it. `tool` is mkfatfsimg or mkqnx6fsimg.

    A byte count is a poor predictor of how large a filesystem must be, so an
    auto-sized image (auto=True) starts from whatever [num_sectors=...] the build
    file carries and grows until the tool stops complaining. The two tools phrase
    the overflow differently -- mkfatfsimg says "No space left", mkqnx6fsimg says
    "Insufficient num_sectors" and states the exact count it needs -- and both are
    handled, the latter by jumping straight to the requested size. An explicitly
    sized image (auto=False) never grows: if you asked for 200M you want to be
    told it does not fit, not to silently get 400M.

    Returns the tool's combined output on success; bb.fatal on failure."""
    import os
    import re
    import subprocess

    if cwd is None:
        cwd = os.path.dirname(out) or None

    output = ''
    for attempt in range(attempts):
        proc = subprocess.run([tool, buildfile, out], capture_output=True,
                              text=True, cwd=cwd, env=env)
        output = (proc.stdout or '') + (proc.stderr or '')
        if proc.returncode == 0:
            return output

        # Only a genuine space failure is retried; anything else (a missing
        # source, a licence problem) is a real error, and inflating the image
        # would only bury it -- a licensing error once got reported as "still
        # fails after 5 attempts at growing it" after quietly inflating a
        # partition from 50MB to 370MB on the way.
        needed = re.search(r'need at least (\d+)', output)
        overflow = needed or 'No space left' in output
        if not auto or not overflow:
            bb.fatal("%s failed on %s:\n%s"
                     % (tool, buildfile, output.strip() or '(no output)'))

        with open(buildfile) as f:
            text = f.read()
        # Anchored to line start: a template may *mention* [num_sectors=...] in a
        # comment (they often explain the hand-maintained value they replace),
        # and rewriting the comment instead of the directive is a silent no-op.
        match = re.search(r'^\[num_sectors=(\d+)\]', text, re.M)
        if not match:
            bb.fatal("%s ran out of space on %s and it has no [num_sectors=...] "
                     "to grow:\n%s"
                     % (tool, buildfile, output.strip() or '(no output)'))

        old = int(match.group(1))
        # Jump straight to what the tool asked for (with the grow factor as
        # headroom) when it told us; otherwise multiply and retry.
        new = int((int(needed.group(1)) if needed else old) * factor)
        new += (-new) % 8            # mkqnx6fsimg wants a multiple of 8
        bb.note("%s did not fit in %d sectors; retrying with %d"
                % (os.path.basename(out), old, new))
        with open(buildfile, 'w') as f:
            f.write(text.replace(match.group(0), '[num_sectors=%d]' % new))

    bb.fatal("%s still does not fit after %d attempts. Either set/raise an "
             "explicit size, or look at the last failure:\n%s"
             % (os.path.basename(out), attempts, output.strip() or '(no output)'))

