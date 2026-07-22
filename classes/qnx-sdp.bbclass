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

# Where in the boot sequence those commands run. Lower runs earlier.
# Conventional bands, so unrelated recipes can be ordered without knowing about
# each other:
#
#     100  hardware drivers, and anything providing a /dev entry
#     300  resource managers and system services built on those
#     500  applications (the default)
#     700  anything wanting the system fully up
#
# Ties keep QNX_IFS_INSTALL order, so listing order stays a usable tiebreak.
QNX_IFS_STARTUP_PRIORITY ?= "500"

# Paths this component provides, waited on after its command is issued.
#
# Priority alone is not enough, and trusting it is a classic QNX boot race: the
# startup script issues commands in order, but a driver started with '&' forks
# and returns immediately, so the next command can easily run before the device
# exists. `waitfor` is what actually blocks until it does -- the same idiom the
# project's own build files use ("devb-virtio ..." followed by "waitfor /dev/hd0").
#
# Declared by the component that *provides* the path, so everything later in the
# sequence is safe without having to know who to wait for.
QNX_IFS_STARTUP_WAITFOR ?= ""

# Seconds before giving up, matching "waitfor /dev/vcon1 4" in the project's
# guest build files.
QNX_IFS_STARTUP_WAITFOR_TIMEOUT ?= "5"

# Raw mkifs lines, for entries that have no staged file behind them: symlinks
# into /tmp or /dev, inline config file bodies, [search=...] for unusual
# locations. Newlines may be written as a literal \n -- bitbake does not process
# escape sequences in variable values, so there is otherwise no way to express a
# multi-line value.
QNX_IFS_EXTRA_ENTRIES ?= ""

# ---------------------------------------------------------------------------
# Per-entry mkifs attributes
# ---------------------------------------------------------------------------
# mkifs takes attributes in brackets before a record -- [uid=0 gid=0 perms=4755]
# and about thirty others (type, prefix, search, data, filter, cksum, sha256,
# chain, module, mtime, dperms, keepsection, ...).
#
# Rather than model each one, the value is passed through verbatim, keyed by the
# staged file's basename. Every record attribute mkifs supports is therefore
# reachable, including any added in a future SDP:
#
#     QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"
#     QNX_IFS_ATTR[tool]     = "data=copy"
#
# Basenames, not paths: bitbake varflag names may only contain [a-zA-Z0-9-_+.@],
# so QNX_IFS_ATTR[/sbin/rpi_gpio] is a parse error rather than a failed lookup.
#
# Attributes that describe the image rather than a record (image, virtual, ram,
# pagesize, cpu, physical, vboot) belong to the boot environment and are set as
# template @VARIABLE@s on the image recipe instead -- see qnx-ifs.bbclass.
QNX_IFS_ATTR[dummy] ?= ""

# Applied to every entry this recipe contributes, before any per-entry value.
QNX_IFS_DEFAULT_ATTR ?= ""

# Override where a staged file lands in the image, when the path derived from
# the stage tree is not what you want. Keyed by basename, value is the full
# destination path:
#
#     QNX_IFS_DEST[myapp] = "/proc/boot/myapp"
QNX_IFS_DEST[dummy] ?= ""

# Varflags do not participate in task signatures, so a change to QNX_IFS_ATTR or
# QNX_IFS_DEST would not invalidate do_install and would silently fail to reach
# the image. These serialise the flags into ordinary variables that do.
QNX_IFS_ATTR_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_IFS_ATTR')}"
QNX_IFS_DEST_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_IFS_DEST')}"

# mkifs resolves a bare source name against its search path, which `-r <root>`
# re-roots onto our stage tree. Only these directories are on that path, so only
# files installed into them can be referenced by bare name.
QNX_IFS_SEARCHABLE_DIRS ?= "bin sbin lib usr/bin usr/sbin usr/lib lib/dll boot/sys"

# Staged content that belongs to the sysroot rather than to any image. Headers
# and static libraries are build inputs for other recipes; putting them in an
# IFS would only waste RAM. Excluded silently -- unlike an unexpected location,
# this is not a mistake worth warning about.
QNX_IFS_EXCLUDE_DIRS ?= "usr/include include"
QNX_IFS_EXCLUDE_SUFFIXES ?= ".a .la .pc .h .hpp .cmake"

def qnx_expand_template(d, template, generated=None):
    """Expand @VARIABLE@ markers in a template against the datastore.

    Shared by the IFS and disk-image classes. bitbake's own ${...} syntax is
    deliberately not used: QNX build files use ${...} for their own variables
    (${PROCESSOR}, ${QNX_TARGET}), and expanding those would corrupt them.

    `generated` supplies values computed at task time, which take precedence."""
    import re
    import os

    if not os.path.isfile(template):
        bb.fatal("template not found: %s" % template)

    generated = generated or {}

    with open(template) as f:
        content = f.read()

    def expand(match):
        name = match.group(1)
        if name in generated:
            return generated[name]
        value = d.getVar(name)
        if value is None:
            bb.fatal("%s references @%s@, which is not set" % (template, name))
        return value

    return re.sub(r'@([A-Z][A-Z0-9_]*)@', expand, content)


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


def qnx_ifs_flags(d, varname):
    """Varflags of varname, minus bitbake's own bookkeeping.

    getVarFlags returns internal flags ("doc", "export", the ?= placeholder)
    alongside the ones a recipe set, and those must not be mistaken for entries."""
    flags = d.getVarFlags(varname) or {}
    return {k: v for k, v in flags.items()
            if not k.startswith('_') and k not in ('doc', 'export', 'dummy',
                                                   'vardeps', 'vardepsexclude',
                                                   'vardepvalue')}

def qnx_ifs_flags_repr(d, varname):
    return repr(sorted(qnx_ifs_flags(d, varname).items()))

python qnx_sdp_write_ifs_dropin() {
    import os

    destdir = d.getVar('D')
    proc = d.getVar('QNX_PROCESSOR')
    stage_root = os.path.join(destdir + d.getVar('QNX_STAGE_DIR'), proc)
    pn = d.getVar('PN')

    attr_map = qnx_ifs_flags(d, 'QNX_IFS_ATTR')
    dest_map = qnx_ifs_flags(d, 'QNX_IFS_DEST')
    default_attr = (d.getVar('QNX_IFS_DEFAULT_ATTR') or '').strip()
    used_attrs = set()
    used_dests = set()

    def record(key, ifs_dest, source, extra_attr=''):
        """One mkifs record: [attributes] destination=source.

        `key` is the staged file's basename. bitbake varflag names may only
        contain [a-zA-Z0-9-_+.@], so a full path cannot be used as a key --
        QNX_IFS_ATTR[/bin/foo] is a parse error, not a lookup that fails."""
        if key in dest_map and dest_map[key].strip():
            used_dests.add(key)
            ifs_dest = dest_map[key].strip()

        parts = [p for p in (default_attr, extra_attr) if p]
        if attr_map.get(key, '').strip():
            used_attrs.add(key)
            parts.append(attr_map[key].strip())

        prefix = '[%s] ' % ' '.join(parts) if parts else ''
        return '%s%s=%s' % (prefix, ifs_dest, source)

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
                    entries.append(record(name, ifs_dest, os.readlink(full),
                                          extra_attr='type=link'))
                elif reldir in searchable:
                    # e.g. aarch64le/bin/qnx-hello  ->  /bin/qnx-hello=qnx-hello
                    entries.append(record(name, ifs_dest, name))
                else:
                    bb.warn("%s: %s/%s is outside the mkifs search path (%s). "
                            "It will not be added to images automatically; add an "
                            "explicit entry via QNX_IFS_EXTRA_ENTRIES."
                            % (pn, reldir or '.', name, ' '.join(searchable)))

    # bitbake stores variable values literally -- "a\nb" keeps the backslash and
    # the n, and a line continuation collapses to a space -- so there is no way
    # to write a multi-line value. Translate the literal escape into a real
    # newline, otherwise mkifs sees several records run together on one line.
    extra = (d.getVar('QNX_IFS_EXTRA_ENTRIES') or '').replace('\\n', '\n').strip()

    # A key that matched nothing is a typo, and would otherwise be silently
    # ignored: the file keeps its default permissions or its original location
    # and nothing says why.
    for key in sorted(set(attr_map) - used_attrs):
        if attr_map[key].strip():
            bb.warn("%s: QNX_IFS_ATTR[%s] matched no staged file. Expected a "
                    "basename, e.g. the name as installed into "
                    "${QNX_STAGE_BINDIR}." % (pn, key))
    for key in sorted(set(dest_map) - used_dests):
        if dest_map[key].strip():
            bb.warn("%s: QNX_IFS_DEST[%s] matched no staged file. Expected a "
                    "basename, e.g. the name as installed into "
                    "${QNX_STAGE_BINDIR}." % (pn, key))

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
    waitfor = (d.getVar('QNX_IFS_STARTUP_WAITFOR') or '').split()

    if waitfor and not startup:
        bb.warn("%s: QNX_IFS_STARTUP_WAITFOR is set but QNX_IFS_STARTUP_CMD is "
                "not, so nothing will ever create %s"
                % (pn, ' '.join(waitfor)))

    if startup:
        prio = (d.getVar('QNX_IFS_STARTUP_PRIORITY') or '500').strip()
        if not prio.isdigit():
            bb.fatal("%s: QNX_IFS_STARTUP_PRIORITY must be a number, got '%s'"
                     % (pn, prio))

        timeout = (d.getVar('QNX_IFS_STARTUP_WAITFOR_TIMEOUT') or '5').strip()

        dropin_dir = destdir + d.getVar('QNX_IFS_DROPIN_DIR')
        bb.utils.mkdirhier(dropin_dir)
        with open(os.path.join(dropin_dir, pn + '.startup'), 'w') as f:
            # The header carries the priority to the image recipe, which cannot
            # read another recipe's variables.
            f.write('### %s prio=%s\n' % (pn, prio))
            f.write(startup + '\n')
            for path in waitfor:
                f.write('waitfor %s %s\n' % (path, timeout))
}
do_install[postfuncs] += "qnx_sdp_write_ifs_dropin"

# Without these, editing any of the drop-in inputs would not invalidate
# do_install, and the change would silently not reach the image.
qnx_sdp_write_ifs_dropin[vardeps] += "QNX_IFS_AUTO_ENTRIES QNX_IFS_STARTUP_CMD \
                                      QNX_IFS_EXTRA_ENTRIES QNX_IFS_SEARCHABLE_DIRS \
                                      QNX_IFS_STARTUP_PRIORITY QNX_IFS_STARTUP_WAITFOR \
                                      QNX_IFS_STARTUP_WAITFOR_TIMEOUT \
                                      QNX_IFS_DEFAULT_ATTR \
                                      QNX_IFS_ATTR_SIG QNX_IFS_DEST_SIG"
