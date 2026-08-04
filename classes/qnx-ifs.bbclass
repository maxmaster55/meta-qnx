# qnx-ifs.bbclass -- assemble a QNX image filesystem (IFS) with mkifs.
#
# This is the Yocto equivalent of the images/ makefiles in a QNX BSP, and the
# .build file is generated rather than maintained by hand.
#
# An image recipe lists what it wants:
#
#     QNX_IFS_INSTALL = "qnx-hello qnx-sysinfo"
#
# and that is the only thing that changes when an application is added. It is
# the direct analogue of IMAGE_INSTALL on Linux: the names become DEPENDS, each
# dependency's files arrive in RECIPE_SYSROOT, and each one's IFS drop-in (see
# qnx-sdp.bbclass) is merged into the generated .build file. No image file is
# edited to gain an application, and no list of files is duplicated anywhere.
#
# The template supplies the parts that genuinely are image-specific -- the boot
# line, the console driver, the startup script -- and marks two injection points:
#
#     @QNX_IFS_STARTUP@   startup-script lines contributed by installed recipes
#     @QNX_IFS_FILES@     mkifs file entries contributed by installed recipes
#
# The mkifs invocation itself mirrors qnx_guests/images/common.mk in the QNX
# hypervisor project:
#
#     mkifs -a<name> -r<install-tree> -v <buildfile> <name>.ifs
#
# What is different is dependency tracking. The makefile version scrapes .build
# files with grep/sed to discover which project files an image stages, so that a
# rebuilt app actually reaches the image. Here that falls out of DEPENDS for
# free, and bitbake reruns do_mkifs when any installed recipe changes.

inherit qnx-sdp deploy

# mkifs reads $PROCESSOR to resolve unqualified binary names out of $QNX_TARGET
# (procnto-smp-instr, ksh, libc.so, ...). The BSP makefiles export both of these.
export PROCESSOR = "${QNX_PROCESSOR}"
export ARCH = "${QNX_PROCESSOR}"

# Recipes to install into this image. Analogous to IMAGE_INSTALL.
QNX_IFS_INSTALL ?= ""
DEPENDS += "${QNX_IFS_INSTALL}"

# Recipes whose startup commands are suppressed in this image. The recipe's
# files are still installed; only the startup script lines are dropped. Use
# this when you want a recipe's binaries or libraries in the image but do not
# want it started automatically at boot.
QNX_IFS_STARTUP_DISABLE ?= ""

# ---------------------------------------------------------------------------
# SDP verification
# ---------------------------------------------------------------------------
# Check the installed SDP against the project's lockfile before building an
# image. It is read-only, offline and takes well under a second, and it turns a
# missing package into a named error instead of mkifs failing with
# "Host file 'x' not available" and a build-file line number.
#
# Set QNX_SDP_CHECK = "0" to skip it. It is also a no-op when neither a lockfile
# nor QNX_QSC_CLT is configured, so this is safe to leave on by default.
QNX_SDP_CHECK ?= "1"
do_mkifs[depends] += "${@'qnx-sdp:do_check_sdp' if d.getVar('QNX_SDP_CHECK') == '1' else ''}"

# ---------------------------------------------------------------------------
# Boot configuration
# ---------------------------------------------------------------------------
# Available to templates as @QNX_STARTUP@, @QNX_IMAGE_ADDR@ and so on.
#
# These describe a boot environment, not a CPU, which is why they live on the
# image and not on the machine: one aarch64le tree legitimately produces both a
# hypervisor host (loaded by the board's firmware at a low address, raw and
# compressed, board-specific startup) and its guests (loaded by qvm at a high
# address, ELF, generic startup). The defaults below are the guest case.
QNX_STARTUP ?= "startup-armv8_fm"
QNX_STARTUP_ARGS ?= "-H"
QNX_KERNEL ?= "procnto-smp-instr"
QNX_KERNEL_ARGS ?= "-v"
QNX_IMAGE_ADDR ?= "0x80000000"
QNX_IMAGE_VIRTUAL ?= "${QNX_PROCESSOR},elf"
QNX_IFS_PATH ?= "/proc/boot:/bin:/usr/bin:/sbin:/usr/sbin"
QNX_IFS_LD_LIBRARY_PATH ?= "/proc/boot:/lib:/usr/lib:/lib/dll"

# What /dev/console is linked to. A guest's console is the virtio console its
# host provides; an image with real hardware overrides this with its UART
# (the RPi5 host image uses /dev/ser10). Used by qnx-base.build.inc, which is
# the reason it is a variable and not a line in each template.
QNX_CONSOLE_DEV ?= "/dev/vcon1"

# ---------------------------------------------------------------------------
# System-wide environment
# ---------------------------------------------------------------------------
# Environment every process on the image gets, written as space-separated
# NAME=value pairs:
#
#     QNX_IFS_ENV += "QT_QPA_PLATFORM=qnx QT_QPA_FONTDIR=/usr/lib/fonts"
#
# It reaches processes two ways, and it needs both:
#
#   the startup script   -- assignments there become the environment procnto
#                           hands to everything the boot script launches, and
#                           to the login shell it ends with. This is what makes
#                           an application started at boot see them.
#   /etc/profile         -- ksh sources it for every interactive shell (ENV is
#                           set in the startup preamble). This is what makes a
#                           shell you open later -- a second console, or ssh --
#                           see the same thing.
#
# Setting only one of the two produces the confusing case where a program works
# from the boot script and not from the prompt, or the reverse.
#
# A value may not contain whitespace: the list is split on it, and the startup
# script has no quoting worth relying on. That is not a real limit for what
# belongs here -- paths, platform names, feature switches.
#
# This is for *system* properties: which QPA platform this board has, where its
# fonts live, whether there is a GPU. Application-private settings belong in the
# application's own launcher, where they override these. In particular an
# application that ships its own Qt must set its own QT_PLUGIN_PATH and library
# path, which is why neither is set here: a global QT_PLUGIN_PATH would send
# every self-contained application at one system-wide plugin directory and load
# a platform plugin built against a different Qt.
QNX_IFS_ENV ?= ""

# ---------------------------------------------------------------------------
# toybox
# ---------------------------------------------------------------------------
# QNX 8 ships no standalone ls, cat, cp, uname or grep -- there is nothing at
# $QNX_TARGET/${PROCESSOR}/bin called any of those. They all come from toybox, a
# single multicall binary that dispatches on argv[0], so an image includes it
# once and adds one link per command it wants. This is what the SDP's own toybox
# documentation prescribes for an IFS.
#
# Without this, a build file referring to `ls` fails with the distinctly
# unhelpful "Host file 'ls' not available" and a build-file line number.
#
# Set QNX_IFS_TOYBOX_CMDS = "" to leave toybox out entirely.
QNX_IFS_TOYBOX ?= "toybox"
QNX_IFS_TOYBOX_PATH ?= "/usr/bin/toybox"
QNX_IFS_TOYBOX_CMDS ?= "ls cat cp mv rm mkdir rmdir ln touch chmod chown \
                        echo printf pwd env printenv which basename dirname \
                        grep egrep fgrep sed find xargs sort uniq cut head tail \
                        wc cmp diff du df stat file readlink realpath \
                        date uname id groups whoami hostname \
                        tar gzip gunzip zcat md5sum sha1sum cksum \
                        more nl seq sleep tee test true false yes clear \
                        dd od xxd split comm paste expand cpio patch strings \
                        install link unlink mkfifo mktemp logname nohup time \
                        timeout truncate tty expr base64 cal chgrp uuidgen"

# Where the links go. /usr/bin for almost everything, with a short list of core
# commands at /bin instead -- which is exactly how the reference images do it,
# 82 links in one directory and 13 in the other, identically in host and guest.
#
# Both directories are on PATH, so this is not about resolution. It is about the
# handful of commands that a script may reasonably name by absolute path, and
# about /bin being populated at all: a boot script or a shebang that says
# /bin/sh or /bin/cat should find one.
#
# This used to put every link in /bin, which moved 82 commands per image relative
# to the reference for no reason anyone chose.
QNX_IFS_TOYBOX_LINK_DIR ?= "/usr/bin"

# df and hostname are here because the reference has them at /bin too -- as real
# SDP binaries rather than toybox links, but at /bin, and a script naming
# /bin/hostname should not care which it got.
QNX_IFS_TOYBOX_BIN_CMDS ?= "cat chmod cp dd echo ln ls mkdir mv pwd rm sed uname \
                            df hostname"

# Recipe-provided:
#   QNX_IFS_NAME     -- basename of the image, also passed to mkifs -a
#   QNX_IFS_TEMPLATE -- .build template containing the @...@ markers
QNX_IFS_NAME ?= "${PN}"
QNX_IFS_TEMPLATE ?= "${S}/${QNX_IFS_NAME}.build.in"

# The generated build file actually handed to mkifs.
QNX_IFS_BUILDFILE ?= "${B}/${QNX_IFS_NAME}.build"

# Root prepended to mkifs's search path. Staged files from every installed recipe
# live here, laid out to mirror $QNX_TARGET (see QNX_STAGE_DIR in qnx-sdp.bbclass),
# so generated entries can refer to them by bare name exactly as the template
# refers to SDP binaries.
QNX_IFS_ROOT ?= "${RECIPE_SYSROOT}${QNX_STAGE_DIR}"

# The recipe sysroot itself, exposed to drop-in fragments as @QNX_IFS_SYSROOT@.
#
# This is how a recipe from a *normal* Yocto layer gets into the image. Our own
# recipes install into the stage tree above and are found by bare name, but a
# stock recipe installs to the ordinary FHS paths (/usr/bin, /usr/lib), which
# are on no mkifs search path, so its fragment names each source by absolute
# path instead. The fragment cannot write that path itself -- it belongs to
# whichever image installs the recipe, not to the recipe -- so it writes the
# marker and the image expands it here. See qnx-image-contract.bbclass.
QNX_IFS_SYSROOT ?= "${RECIPE_SYSROOT}"

# Additional roots, searched after the recipe sysroot and before $QNX_TARGET.
# mkifs accepts -r repeatedly and searches them left to right, which is what lets
# a board layer add a BSP install tree holding binaries the SDP does not ship --
# an RPi5 host image needs startup-bcm2712-rpi5, i2c-dwc-rpi5, gpio-rp1 and
# friends, none of which exist under $QNX_TARGET.
QNX_IFS_EXTRA_ROOTS ?= ""
QNX_IFS_ROOTS ?= "${QNX_IFS_ROOT} ${QNX_IFS_EXTRA_ROOTS}"

# ---------------------------------------------------------------------------
# Shared-library closure
# ---------------------------------------------------------------------------
# mkifs has NO dependency resolution. `-r` adds search paths for the files a
# build file *names*; nothing else ever enters the image. A build file that
# lists pci-server and not libc.so produces an image where pci-server exists and
# cannot run -- procnto reports errno 83, ELIBACC, and the binary looks broken
# when it is merely alone. Nothing catches this before the board: dumpifs
# happily lists an image whose every executable is unloadable.
#
# The QNX BSP answer is a hand-maintained list -- rpi5-hypervisor.build carries
# ~200 lines of "General shared libraries" -- which has to be re-derived by hand
# every time a recipe gains a dependency. Instead this reads DT_NEEDED out of
# every binary the build file references, transitively, and appends whatever is
# missing. The loader comes with it: PT_INTERP asks for /usr/lib/ldqnx-64.so.2,
# which the startup preamble's procmgr_symlink points at /proc/boot, so the
# loader is staged there.
#
# Set QNX_IFS_AUTO_DEPS = "0" to write the list by hand instead.
QNX_IFS_AUTO_DEPS ?= "1"

# The dynamic loader, staged at /proc/boot to match the procmgr_symlink in
# qnx-startup-preamble.build.inc.
QNX_IFS_LOADER ?= "ldqnx-64.so.2"

# Sonames never to add, for a library that is deliberately absent or supplied by
# something the closure cannot see. Space separated, matched on basename.
QNX_IFS_DEP_EXCLUDE ?= ""

# Where mkifs looks under each -r root, and equally where a resolved library is
# placed in the image: a library found at <root>/${PROCESSOR}/usr/lib lands at
# /usr/lib, which is what LD_LIBRARY_PATH in the boot block already covers.
QNX_IFS_SEARCH_SUBDIRS ?= "lib lib/dll usr/lib bin sbin usr/bin usr/sbin usr/libexec boot/sys"


def qnx_ifs_search_dirs(d):
    """The directories mkifs searches, in its own order: each -r root first,
    left to right, then $QNX_TARGET.

    Each entry is (host directory, image directory). The second half is what
    makes the closure place a library correctly: one found under a root's
    usr/lib belongs at /usr/lib in the image, which is where the boot block's
    LD_LIBRARY_PATH already looks."""
    import os

    processor = d.getVar('QNX_PROCESSOR')
    subdirs = (d.getVar('QNX_IFS_SEARCH_SUBDIRS') or '').split()

    roots = (d.getVar('QNX_IFS_ROOTS') or '').split()
    roots.append(d.getVar('QNX_TARGET'))

    return [(os.path.join(root, processor, sub), '/' + sub)
            for root in roots for sub in subdirs]


def qnx_ifs_resolve(name, search_dirs):
    """Resolve a build-file source the way mkifs would.

    Returns (host path, image directory), or (None, None)."""
    import os

    if os.path.isabs(name):
        return (name, None) if os.path.isfile(name) else (None, None)
    for host_dir, image_dir in search_dirs:
        candidate = os.path.join(host_dir, name)
        if os.path.isfile(candidate):
            return candidate, image_dir
    return None, None


def qnx_ifs_buildfile_records(text):
    """Every (destination, source) a generated build file declares.

    Skips the boot and startup script blocks and any inline `= { ... }` body:
    a command named in a script is not a file record, which is precisely the
    trap that left pipe and slogger2 out of the image while the script called
    them by name.

    Destinations matter as much as sources. Two records may name different host
    files and still collide in the image -- a library staged by a recipe into
    its sysroot and the SDP's copy of the same soname are different files with
    the same destination -- and mkifs rejects that outright with "Entry
    'usr/lib/libbz2.so.1' redefined"."""
    import re

    # Inline bodies, including the boot and startup-script blocks.
    text = re.sub(r'=\s*\{.*?\n\}', '=', text, flags=re.S)

    records = []
    for line in text.splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        is_link = '[type=link]' in line
        # Strip the leading attribute groups ([uid=0 gid=0 perms=0755] ...).
        while line.startswith('['):
            end = line.find(']')
            if end < 0:
                break
            line = line[end + 1:].strip()
        if not line or line.startswith('['):
            continue

        if '=' in line:
            dest, source = line.split('=', 1)
            dest, source = dest.strip(), source.strip()
        else:
            dest, source = line, line

        # A link creates no payload and its right-hand side is an image path
        # rather than a host file -- but it still claims its destination.
        records.append((dest, None if is_link else source))
    return records


def qnx_ifs_needed(path, readelf):
    """DT_NEEDED sonames of an ELF file; empty for anything else."""
    import re
    import subprocess

    try:
        out = subprocess.run([readelf, '-d', path], check=False,
                             stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             universal_newlines=True).stdout
    except OSError:
        return []
    return re.findall(r'\(NEEDED\).*?\[([^\]]+)\]', out)


def qnx_ifs_dep_records(d, text):
    """Build-file records for every library `text` needs but does not carry."""
    import os

    search_dirs = qnx_ifs_search_dirs(d)
    readelf = os.path.join(d.getVar('QNX_HOST'), 'usr', 'bin',
                           d.getVar('QNX_TOOL_PREFIX') + 'readelf')
    if not os.path.isfile(readelf):
        bb.fatal("QNX_IFS_AUTO_DEPS needs %s, which does not exist" % readelf)

    excluded = set((d.getVar('QNX_IFS_DEP_EXCLUDE') or '').split())

    # Compared by realpath, since a build file naming `libcam.so` gets the
    # symlink *and* its libcam.so.2 target, which is what DT_NEEDED asks for.
    def real(path):
        return os.path.realpath(path)

    present = set()
    claimed = set()
    queue = []
    for dest, source in qnx_ifs_buildfile_records(text):
        claimed.add(dest)
        if source is None:
            continue
        resolved, _ = qnx_ifs_resolve(source, search_dirs)
        if resolved:
            present.add(real(resolved))
            queue.append(resolved)

    records = []
    missing = []
    seen_soname = set()

    while queue:
        for soname in qnx_ifs_needed(queue.pop(0), readelf):
            if soname in seen_soname or soname in excluded:
                continue
            seen_soname.add(soname)

            resolved, image_dir = qnx_ifs_resolve(soname, search_dirs)
            if not resolved:
                missing.append(soname)
                continue
            if real(resolved) in present:
                continue

            present.add(real(resolved))
            queue.append(resolved)

            # The image already has something at that path -- typically a
            # recipe that built this library itself, whose copy in its sysroot
            # is a different file from the SDP's. Its dependencies still have to
            # be walked, which is why this comes after the queue append, but
            # emitting a second record would be "Entry ... redefined".
            dest = '%s/%s' % (image_dir, soname)
            if dest in claimed:
                continue

            claimed.add(dest)
            records.append('%s=%s' % (dest, resolved))

    if missing:
        # Not fatal: a library may legitimately come from a data partition, and
        # failing the build over one would be worse than a boot-time diagnostic.
        bb.warn("%s: no host file for DT_NEEDED %s -- anything linking them "
                "will fail at startup with ELIBACC. Add the recipe that "
                "provides them, or list them in QNX_IFS_DEP_EXCLUDE if they "
                "arrive some other way."
                % (d.getVar('PN'), ', '.join(sorted(missing))))

    if not records:
        return []

    header = ['',
              '### shared-library closure (%d libraries, resolved from DT_NEEDED)'
              % len(records),
              '[uid=0 gid=0 perms=0755]']

    # PT_INTERP asks for /usr/lib/ldqnx-64.so.2, which the startup preamble's
    # procmgr_symlink redirects to /proc/boot -- so the loader goes there, which
    # a bare destination is exactly what mkifs does.
    loader = d.getVar('QNX_IFS_LOADER')
    loader_path, _ = qnx_ifs_resolve(loader, search_dirs)
    if loader_path:
        header.append('%s=%s' % (loader, loader_path))
    else:
        bb.warn("%s: dynamic binaries are in this image but its loader (%s) "
                "was not found on any mkifs search path; nothing will run."
                % (d.getVar('PN'), loader))

    return header + sorted(records)


def qnx_ifs_expand_install(d, names, dropin_dir):
    """Expand packagegroups in an install list, depth first.

    A name whose sysroot carries a <name>.install drop-in is a group (see
    qnx-packagegroup.bbclass); it is replaced by its members, which may
    themselves be groups. Everything else passes through untouched.

    Order is preserved and a name already present is not added twice, so an
    image that installs a group *and* one of its members -- to pin its position
    in the startup sequence, say -- gets the member once, where it first asked
    for it."""
    import os

    out = []
    seen = set()

    def walk(name, trail):
        if name in seen:
            return
        if name in trail:
            bb.fatal("%s: packagegroup cycle: %s"
                     % (d.getVar('PN'), ' -> '.join(list(trail) + [name])))

        path = os.path.join(dropin_dir, name + '.install')
        if not os.path.isfile(path):
            seen.add(name)
            out.append(name)
            return

        # A group contributes nothing itself; it is replaced by its members.
        # It is still marked seen, so installing the same group twice is a
        # no-op rather than a repeated expansion.
        seen.add(name)
        with open(path) as f:
            for line in f:
                line = line.split('#', 1)[0].strip()
                if line:
                    walk(line, trail + (name,))

    for name in names:
        walk(name, ())
    return out


python do_generate_buildfile() {
    import os
    import re

    template = d.getVar('QNX_IFS_TEMPLATE')
    if not os.path.isfile(template):
        bb.fatal("mkifs template not found: %s" % template)

    # QNX_IFS_DROPIN_DIR is already rooted at QNX_STAGE_DIR, so it is joined to
    # RECIPE_SYSROOT -- not to QNX_IFS_ROOT, which would double the stage dir.
    dropin_dir = d.getVar('RECIPE_SYSROOT') + d.getVar('QNX_IFS_DROPIN_DIR')
    installed = qnx_ifs_expand_install(
        d, (d.getVar('QNX_IFS_INSTALL') or '').split(), dropin_dir)

    def read_dropins(suffix):
        """Read the <pn><suffix> drop-ins of everything installed.

        Iterating QNX_IFS_INSTALL rather than globbing the directory keeps the
        result deterministic and independent of what else happens to be in the
        shared sysroot."""
        out = []
        for index, pn in enumerate(installed):
            path = os.path.join(dropin_dir, pn + suffix)
            if os.path.isfile(path):
                with open(path) as f:
                    text = f.read().rstrip('\n')

                # @VARIABLE@ markers in a fragment are expanded here, in the
                # image's context rather than the contributing recipe's. That is
                # what lets a recipe refer to @QNX_IFS_ROOT@ -- the search root
                # mkifs is given -- which it cannot know itself, since the path
                # belongs to whichever image installs it. Expanding after
                # insertion would not work: the template substitution does not
                # rescan the text it has just inserted.
                def expand_fragment(match, pn=pn):
                    name = match.group(1)
                    value = d.getVar(name)
                    if value is None:
                        bb.fatal("%s: fragment from '%s' references @%s@, which "
                                 "is not set" % (d.getVar('PN'), pn, name))
                    return value

                # Two or more characters, NOT one. A single-letter marker is
                # indistinguishable from QNX's own crypt format, which delimits
                # the hash type the same way:
                #
                #     root:@S@<base64 hash>@<base64 salt>:...
                #
                # With [A-Z0-9_]* that @S@ matched, and every image this layer
                # built got d.getVar('S') -- the recipe's source directory --
                # substituted into root's password field. No password could ever
                # be verified, and nothing said so: the file looked plausible,
                # ssh just refused every login.
                #
                # Nothing legitimately needs a one-character marker, so the
                # narrower pattern costs nothing.
                text = re.sub(r'@([A-Z][A-Z0-9_]+)@', expand_fragment, text)
                out.append((index, pn, text))
        return out

    files = '\n'.join(text for _, _, text in read_dropins('.files'))

    # Startup fragments are ordered by QNX_IFS_STARTUP_AFTER dependencies,
    # carried in the header ("### <pn> after=dep1,dep2"). The assembler
    # topologically sorts them: a recipe naming another in AFTER is guaranteed
    # to come after it in the script. Recipes with no constraints, or at the
    # same depth in the graph, fall back to QNX_IFS_INSTALL order.

    disabled = set((d.getVar('QNX_IFS_STARTUP_DISABLE') or '').split())
    fragments = read_dropins('.startup')

    if disabled:
        fragments = [(idx, pn, text) for idx, pn, text in fragments
                     if pn not in disabled]

    def after_of(pn, text):
        match = re.match(r'###\s+\S+\s+after=(.*)', text)
        if match:
            raw = match.group(1).strip()
            return raw.split(',') if raw else []
        bb.warn("%s: startup fragment from '%s' has no after= header"
                % (d.getVar('PN'), pn))
        return []

    present = {item[1] for item in fragments}
    deps = {}
    for _, pn, text in fragments:
        after = after_of(pn, text)
        for dep in after:
            if dep not in present:
                bb.warn("%s: '%s' declares QNX_IFS_STARTUP_AFTER = '%s', "
                        "but '%s' has no startup in this image"
                        % (d.getVar('PN'), pn, dep, dep))
        deps[pn] = [a for a in after if a in present]

    from collections import defaultdict

    install_idx = {item[1]: item[0] for item in fragments}
    by_pn = {item[1]: item for item in fragments}

    in_degree = {pn: len(deps.get(pn, [])) for pn in present}
    successors = defaultdict(list)
    for pn in present:
        for dep in deps.get(pn, []):
            successors[dep].append(pn)

    ready = sorted([pn for pn in present if in_degree[pn] == 0],
                   key=lambda p: install_idx.get(p, 0))
    ordered = []
    while ready:
        pn = ready.pop(0)
        ordered.append(by_pn[pn])
        for s in successors[pn]:
            in_degree[s] -= 1
            if in_degree[s] == 0:
                ready.append(s)
        ready.sort(key=lambda p: install_idx.get(p, 0))

    if len(ordered) != len(present):
        cycle = sorted(present - {item[1] for item in ordered})
        bb.fatal("%s: startup ordering cycle among: %s"
                 % (d.getVar('PN'), ', '.join(cycle)))

    startup = '\n'.join(text for _, _, text in ordered)

    # A recipe that stages nothing and starts nothing is almost certainly a
    # mistake -- a typo in QNX_IFS_INSTALL, or a recipe that never installed
    # into ${QNX_STAGE_DIR} -- and would otherwise produce a silently empty image.
    #
    # Except for the recipes that mean it. A BSP puts a tree of binaries where
    # mkifs can find them and contributes no records at all, because an image
    # wants a handful of them and names those itself -- see qnx-bsp.bbclass.
    # Warning about those is telling the truth and being wrong about it, so they
    # opt out with QNX_IFS_STAGE_ONLY and the check keeps its meaning for
    # everything else.
    for pn in installed:
        if os.path.isfile(os.path.join(dropin_dir, pn + '.stageonly')):
            continue
        if not any(os.path.isfile(os.path.join(dropin_dir, pn + s))
                   for s in ('.files', '.startup')):
            bb.warn("%s: '%s' is in QNX_IFS_INSTALL but contributes nothing to the "
                    "image. Does it install into ${QNX_STAGE_DIR} and inherit "
                    "qnx-sdp? If it is a stage-only recipe whose files the "
                    "template names by hand, set QNX_IFS_STAGE_ONLY = \"1\" in it."
                    % (d.getVar('PN'), pn))

    # Include-resolved, not raw: a template is allowed to keep the generated
    # sections in a shared fragment, and checking the unresolved text would
    # reject it for a marker that is in fact present.
    if '@QNX_IFS_FILES@' not in qnx_read_template(d, template):
        bb.fatal("%s contains no @QNX_IFS_FILES@ marker, so installed recipes "
                 "have nowhere to go" % template)

    # Any @VARIABLE@ in the template is expanded from the datastore, with the
    # two generated sections above taking precedence. That is what lets one
    # template serve different boot environments: a hypervisor host and a guest
    # differ in startup program, image address and virtual type, not in
    # structure. Those are image properties, not machine properties -- a single
    # aarch64le tree legitimately produces both, exactly as the project's
    # qnx_host/ and qnx_guests/ do today.
    #
    # bitbake's own ${...} syntax is deliberately not used for this: mkifs build
    # files use ${...} for their own variables (${PROCESSOR}, ${QNX_TARGET}),
    # and expanding those here would corrupt them.
    # toybox: the binary once, then a link per command. Appended to the files
    # section rather than needing its own marker, so existing templates get it
    # without modification.
    toybox_cmds = (d.getVar('QNX_IFS_TOYBOX_CMDS') or '').split()
    if toybox_cmds:
        toybox = d.getVar('QNX_IFS_TOYBOX')
        toybox_path = d.getVar('QNX_IFS_TOYBOX_PATH')
        link_dir = (d.getVar('QNX_IFS_TOYBOX_LINK_DIR') or '/usr/bin').rstrip('/')
        bin_cmds = set((d.getVar('QNX_IFS_TOYBOX_BIN_CMDS') or '').split())

        lines = ['', '### toybox (multicall: one binary, %d commands)'
                 % len(toybox_cmds),
                 '%s=%s' % (toybox_path, toybox)]
        # Absolute link targets. The SDP docs show a bare "=toybox", but a
        # symlink target without a leading slash resolves relative to the link's
        # own directory -- /bin/ls would look for /bin/toybox, which is not
        # where it lives.
        #
        # QNX_IFS_TOYBOX_BIN_CMDS go to /bin, everything else to link_dir. A
        # command named in BIN_CMDS but not in CMDS is simply not in the image;
        # it is a subset selector, not a second list.
        lines += ['[type=link] %s/%s=%s'
                  % ('/bin' if cmd in bin_cmds else link_dir, cmd, toybox_path)
                  for cmd in toybox_cmds]
        files = files + '\n'.join(lines) + '\n'

    # QNX_IFS_ENV, in the two spellings the two places want. Both markers are
    # in shared fragments and both expand to nothing when the list is empty, so
    # an image that sets no environment is unaffected.
    env_pairs = []
    for item in (d.getVar('QNX_IFS_ENV') or '').split():
        if '=' not in item:
            bb.fatal("%s: QNX_IFS_ENV entry '%s' is not NAME=value"
                     % (d.getVar('PN'), item))
        env_pairs.append(item)

    env_script = '\n'.join('    %s' % pair for pair in env_pairs)
    env_profile = '\n'.join('export %s' % pair for pair in env_pairs)

    content = qnx_expand_template(d, template, {
        'QNX_IFS_FILES': files,
        'QNX_IFS_STARTUP': startup,
        'QNX_IFS_ENV_SCRIPT': env_script,
        'QNX_IFS_ENV_PROFILE': env_profile,
    })

    # Appended to the finished text, not to the files section: the closure has
    # to see every record the image ends up with, including the ones the
    # template writes itself and the toybox block above. Records are position
    # independent, so the end of the file is as good as anywhere -- but the
    # attribute prefix in the block is not optional, since mkifs attributes
    # persist and this inherits whatever state the template left behind.
    if oe.types.boolean(d.getVar('QNX_IFS_AUTO_DEPS') or '0'):
        records = qnx_ifs_dep_records(d, content)
        if records:
            content = content.rstrip('\n') + '\n' + '\n'.join(records) + '\n'
            bb.note("%s: shared-library closure added %d files"
                    % (d.getVar('PN'),
                       sum(1 for record in records if '=' in record)))

    # User ssh keys, from the IMAGE rather than from a component.
    #
    # Appended here for the same reason the closure above is: these are the
    # image's own records, and a component cannot write them. qnx-ssh is one
    # recipe shared by every image, so a value set in an image recipe never
    # reaches its datastore -- the guest authorising a key would have silently
    # produced nothing, which is exactly what it did until this moved.
    key_records = []

    # Public keys can also be named by file, which is what you want for an
    # operator's own key: it stays in ~/.ssh and never gets pasted into a
    # git-tracked recipe. Contents are appended to whatever the variable holds.
    authorized = (d.getVar('QNX_SSH_AUTHORIZED_KEYS') or '').strip()
    for path in (d.getVar('QNX_SSH_AUTHORIZED_KEYS_FILE') or '').split():
        if not os.path.isfile(path):
            bb.fatal("%s: QNX_SSH_AUTHORIZED_KEYS_FILE names '%s', which does not "
                     "exist. It is a path on the build host to a PUBLIC key (.pub)."
                     % (d.getVar('PN'), path))
        with open(path) as f:
            authorized = (authorized + ' ' + f.read().strip()).strip()

    if authorized:
        # Split on key TYPE tokens, not on newlines. bitbake's += joins with a
        # space, so two keys appended separately arrive as one line -- and
        # authorized_keys is one key per line, so writing that out gives a file
        # sshd reads as a single malformed entry and honours neither key.
        #
        # A public key is "<type> <base64> [comment]", and a comment may contain
        # spaces, so the only reliable boundary is the next type token.
        types = ('ssh-', 'ecdsa-', 'sk-ssh-', 'sk-ecdsa-')
        lines, current = [], []
        for token in authorized.split():
            if token.startswith(types) and current:
                lines.append(' '.join(current))
                current = []
            current.append(token)
        if current:
            lines.append(' '.join(current))

        key_records.append('[perms=0600 uid=0 gid=0] /root/.ssh/authorized_keys = {\n'
                           + '\n'.join(lines) + '\n}')

    identity = (d.getVar('QNX_SSH_IDENTITY') or '').strip()
    if identity:
        dest = (d.getVar('QNX_SSH_IDENTITY_DEST') or '/root/.ssh/id_ed25519').strip()
        if not os.path.isfile(identity):
            bb.fatal("%s: QNX_SSH_IDENTITY is '%s', which does not exist. It is a "
                     "path on the build host to a PRIVATE key, installed into the "
                     "image as %s." % (d.getVar('PN'), identity, dest))
        key_records.append('[perms=0600 uid=0 gid=0] %s=%s' % (dest, identity))

        # Extra paths the same key has to be reachable at. Links rather than
        # copies: it is one key, and two files that can drift apart is exactly
        # what this should not be.
        for link in (d.getVar('QNX_SSH_IDENTITY_LINKS') or '').split():
            key_records.append('[type=link] %s=%s' % (link, dest))

    if key_records:
        content = (content.rstrip('\n') + '\n\n'
                   + '### ssh keys (QNX_SSH_AUTHORIZED_KEYS / QNX_SSH_IDENTITY)\n'
                   + '\n'.join(key_records) + '\n')

    buildfile = d.getVar('QNX_IFS_BUILDFILE')
    bb.utils.mkdirhier(os.path.dirname(buildfile))
    with open(buildfile, 'w') as f:
        f.write(content)

    bb.note("generated %s from %s (%d recipes installed)"
            % (buildfile, template, len(installed)))
}
addtask generate_buildfile after do_configure before do_mkifs
do_generate_buildfile[vardeps] += "QNX_IFS_INSTALL QNX_IFS_STARTUP_DISABLE \
                                   QNX_IFS_ENV \
                                   QNX_SSH_AUTHORIZED_KEYS QNX_SSH_AUTHORIZED_KEYS_FILE \
                                   QNX_SSH_IDENTITY \
                                   QNX_SSH_IDENTITY_DEST QNX_SSH_IDENTITY_LINKS \
                                   QNX_IFS_AUTO_DEPS QNX_IFS_DEP_EXCLUDE \
                                   QNX_IFS_LOADER QNX_IFS_SEARCH_SUBDIRS \
                                   QNX_IFS_TOYBOX_CMDS QNX_IFS_TOYBOX_PATH \
                                   QNX_IFS_TOYBOX_LINK_DIR QNX_IFS_TOYBOX_BIN_CMDS"

# Editing a shared fragment must rebuild the images that include it. The
# template itself is already tracked (it comes through SRC_URI); the fragments
# come off the include path, which bitbake knows nothing about.
do_generate_buildfile[file-checksums] += "${@qnx_template_include_checksums(d)}"

do_mkifs() {
	mkdir -p ${B}
	cd ${B}

	roots=""
	for r in ${QNX_IFS_ROOTS}; do
		if [ ! -d "$r" ]; then
			bbfatal "mkifs search root does not exist: $r"
		fi
		roots="$roots -r$r"
	done

	# -a<name>: name embedded in the image and used for the .sym files mkifs
	#           drops beside it (procnto-*.sym, startup-*.sym), which are what
	#           you feed gdb when debugging the image.
	mkifs -a${QNX_IFS_NAME} $roots -v \
		${QNX_IFS_BUILDFILE} ${QNX_IFS_NAME}.ifs
}
addtask mkifs after do_compile before do_install

do_install[noexec] = "1"

# ---------------------------------------------------------------------------
# dumpifs -- see what actually went in
# ---------------------------------------------------------------------------
# `bitbake -c dumpifs <image>` prints the image's contents on the console,
# building the image first if needed. Saves finding dumpifs and the deploy
# directory by hand; a python task because a shell task's output only goes to
# the log file.
python do_dumpifs() {
    import os
    import subprocess

    ifs = os.path.join(d.getVar('B'), d.getVar('QNX_IFS_NAME') + '.ifs')
    if not os.path.isfile(ifs):
        bb.fatal("%s does not exist -- did do_mkifs run?" % ifs)

    # A python task's subprocess sees bitbake's environment, not the generated
    # shell-task one, so the SDP paths must be passed explicitly (same story as
    # qnx-disk's do_compile).
    env = dict(os.environ)
    for var in ('HOME', 'QNX_HOST', 'QNX_TARGET', 'PATH'):
        value = d.getVar(var)
        if value:
            env[var] = value

    proc = subprocess.run(['dumpifs', '-v', ifs], capture_output=True,
                          text=True, env=env)
    if proc.returncode != 0:
        bb.fatal("dumpifs failed:\n%s" % (proc.stderr or proc.stdout))
    bb.plain(proc.stdout)
}
addtask dumpifs after do_mkifs
do_dumpifs[nostamp] = "1"
do_dumpifs[doc] = "Print the contents of the built IFS"

# The generated build file, for `bitbake -c dumpbuild <image>` (qnx-sdp).
# After generate_buildfile rather than mkifs: reading what was asked for should
# not require the image to build, and when mkifs is what failed this is exactly
# the file you want to look at.
QNX_BUILDFILES = "${QNX_IFS_BUILDFILE}"
addtask dumpbuild after do_generate_buildfile

do_deploy() {
	install -d ${DEPLOYDIR}
	install -m 0644 ${B}/${QNX_IFS_NAME}.ifs ${DEPLOYDIR}/

	# Ship the generated build file next to the image: when something is in the
	# IFS and you cannot see why, this is the file that explains it.
	install -m 0644 ${QNX_IFS_BUILDFILE} ${DEPLOYDIR}/${QNX_IFS_NAME}.build

	# Symbol files are optional (mkifs only writes them for images with a
	# startup/kernel) but are needed for source-level debugging when present.
	for sym in ${B}/*.sym; do
		[ -e "$sym" ] || continue
		install -m 0644 "$sym" ${DEPLOYDIR}/
	done
}
addtask deploy after do_mkifs before do_build

# The identity is a file outside the layer, so nothing else makes its contents
# part of the signature -- replacing the key would otherwise leave the image
# untouched.
do_generate_buildfile[file-checksums] += "${@('%s:True' % d.getVar('QNX_SSH_IDENTITY')) if (d.getVar('QNX_SSH_IDENTITY') or '').strip() else ''}"

# Named .pub files are outside the layer, so their contents are not otherwise
# part of the signature -- swapping a key would leave the image untouched.
do_generate_buildfile[file-checksums] += "${@' '.join('%s:True' % p for p in (d.getVar('QNX_SSH_AUTHORIZED_KEYS_FILE') or '').split())}"
