# qnx-image-contract.bbclass -- how any recipe declares what it puts in an image.
#
# One image should never have to be edited to gain an application, and no image
# should care *how* the recipe providing that application was built. This class
# is the contract that makes both true, and it is deliberately the only place
# that knows the format:
#
#   ${QNX_IFS_DROPIN_DIR}/${PN}.files     mkifs entries (one per installed file)
#   ${QNX_IFS_DROPIN_DIR}/${PN}.startup   lines for the boot script, if any
#   ${QNX_IFS_DROPIN_DIR}/${PN}.install   further recipes to pull in (see
#                                         qnx-packagegroup.bbclass)
#
# An image recipe concatenates the fragments of everything it installs into a
# generated .build file (qnx-ifs.bbclass). Same idea as an /etc/something.d
# directory: the component owns its own entry, and the thing consuming it never
# enumerates its members.
#
# Two kinds of recipe write these fragments, which is the reason this is a class
# of its own rather than part of qnx-sdp:
#
#   qnx-sdp        our own recipes. They install into the stage tree
#                  (${QNX_STAGE_DIR}/${PROCESSOR}/{bin,sbin,lib}), which is
#                  laid out exactly as `mkifs -r <root>` wants, so an entry can
#                  name its source by bare name and let mkifs find it.
#
#   qnx-toolchain  stock recipes from normal Yocto layers (oe-core, meta-oe),
#                  built for QNX but installing to the ordinary FHS paths
#                  (${bindir}, ${libdir}). Those paths are not on any mkifs
#                  search path, so their entries name the source by absolute
#                  path into the image's own sysroot instead.
#
# Everything else -- attributes, destination overrides, startup ordering, the
# ELF sanity check -- is identical for both, and lives here once.

# ---------------------------------------------------------------------------
# The stage tree
# ---------------------------------------------------------------------------
# Defined here rather than in qnx-sdp because the drop-in directory lives inside
# it, and a stock recipe writing drop-ins needs it too without taking on the
# rest of qnx-sdp's toolchain surgery.
QNX_STAGE_DIR ?= "/qnx-stage"
QNX_IFS_DROPIN_DIR ?= "${QNX_STAGE_DIR}/ifs.d"

# ---------------------------------------------------------------------------
# What this recipe contributes
# ---------------------------------------------------------------------------
# By default the .files fragment is derived automatically from whatever the
# recipe installed, so a normal application recipe declares nothing at all.
# Set to "0" in a recipe that wants to spell out its entries by hand.
QNX_IFS_AUTO_ENTRIES ?= "1"

# Set in a recipe that stages files for an image's template to name by hand, and
# deliberately contributes no records of its own. A BSP is the case: it unpacks a
# tree of board binaries into the stage tree where mkifs can find them, and each
# image names the few it wants.
#
# It exists only to keep the "contributes nothing to the image" check honest.
# That check catches a real and common mistake -- a typo in QNX_IFS_INSTALL, a
# recipe that installed outside ${QNX_STAGE_DIR} -- and a warning that also fires
# on recipes doing the right thing is a warning people learn to scroll past.
QNX_IFS_STAGE_ONLY ?= "0"

# Command(s) to run from the image's startup script, e.g. "my-daemon &".
QNX_IFS_STARTUP_CMD ?= ""

# Recipes whose startup commands must run before this one. Works like
# systemd's After=: the image assembler topologically sorts all startup
# fragments, placing this recipe's command after every recipe named here.
# Dependencies on recipes not present in the image are silently ignored, so
# a recipe can safely name optional prerequisites.
#
# Recipes with no AFTER constraints are ordered by their position in
# QNX_IFS_INSTALL, which is also the tiebreak when the dependency graph does
# not force an order. That makes the install list the final word on ordering
# for recipes that do not declare constraints.
QNX_IFS_STARTUP_AFTER ?= ""

# Paths this component provides, waited on after its command is issued.
#
# Ordering alone is not enough, and trusting it is a classic QNX boot race: the
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

# Raw mkifs lines, for entries that have no installed file behind them: symlinks
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
# installed file's basename. Every record attribute mkifs supports is therefore
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

# Override where an installed file lands in the image, when the path derived
# from the install tree is not what you want. Keyed by basename, value is the
# full destination path:
#
#     QNX_IFS_DEST[myapp] = "/proc/boot/myapp"
QNX_IFS_DEST[dummy] ?= ""

# Varflags do not participate in task signatures, so a change to QNX_IFS_ATTR or
# QNX_IFS_DEST would not invalidate do_install and would silently fail to reach
# the image. These serialise the flags into ordinary variables that do.
QNX_IFS_ATTR_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_IFS_ATTR')}"
QNX_IFS_DEST_SIG = "${@qnx_ifs_flags_repr(d, 'QNX_IFS_DEST')}"

# ---------------------------------------------------------------------------
# How the installed tree is turned into entries
# ---------------------------------------------------------------------------
# The two knobs that differ between a qnx-sdp recipe and a stock one. Everything
# else about harvesting is shared.
#
# QNX_IMAGE_HARVEST_DIRS -- directories under ${D} to walk, relative to which
# each entry's image path is computed. Empty means ${D} itself.
QNX_IMAGE_HARVEST_DIRS ?= ""

# QNX_IMAGE_SOURCE_STYLE -- how an entry names the file it copies in:
#
#   search   bare basename, resolved by mkifs against its search path (which
#            `-r <root>` re-roots onto the stage tree). Only files in
#            QNX_IFS_SEARCHABLE_DIRS can be named this way.
#
#   sysroot  absolute path built from QNX_IMAGE_SOURCE_PREFIX plus the file's
#            path. The prefix is an @VARIABLE@ marker expanded by the *image*,
#            not here, because the path belongs to whichever image installs the
#            recipe -- it is that image's RECIPE_SYSROOT, which the contributing
#            recipe cannot know.
QNX_IMAGE_SOURCE_STYLE ?= "sysroot"
QNX_IMAGE_SOURCE_PREFIX ?= "@QNX_IFS_SYSROOT@"

# mkifs resolves a bare source name against its search path. Only these
# directories are on that path, so under the "search" style only files installed
# into them can be referenced by bare name.
QNX_IFS_SEARCHABLE_DIRS ?= "bin sbin lib usr/bin usr/sbin usr/lib lib/dll boot/sys"

# Installed content that belongs to the sysroot rather than to any image.
# Headers and static libraries are build inputs for other recipes; man pages,
# locales and documentation are dead weight in a RAM-resident IFS. Excluded
# silently -- unlike an unexpected location, this is not a mistake worth
# warning about.
QNX_IFS_EXCLUDE_DIRS ?= "usr/include include usr/share/man usr/share/doc \
                         usr/share/info usr/share/locale usr/src \
                         usr/lib/pkgconfig usr/lib/cmake"
QNX_IFS_EXCLUDE_SUFFIXES ?= ".a .la .pc .h .hpp .cmake"

# ---------------------------------------------------------------------------
# QA: installed binaries must be target ELFs
# ---------------------------------------------------------------------------
# A build system that ignores ${CC} -- a makefile hardcoding gcc, a configure
# step finding the host compiler -- produces x86-64 Linux binaries that install,
# link and mkifs perfectly well, and fail only on the board with an unhelpful
# exec error. Checking e_machine at install time turns that into a build error
# naming the file.
#
# Set QNX_ELF_CHECK = "0" in a recipe to skip it (a recipe staging foreign
# firmware blobs that happen to be ELF, say).
QNX_ELF_CHECK ?= "1"

# Expected ELF e_machine value: 183 is EM_AARCH64. A machine conf for another
# architecture overrides this alongside QNX_PROCESSOR.
QNX_ELF_MACHINE ?= "183"

# Which part of ${D} to check. Defaults to the harvested tree, so a recipe that
# also installs host-side helpers is not tripped up by them.
QNX_ELF_CHECK_DIRS ?= "${QNX_IMAGE_HARVEST_DIRS}"


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


def qnx_elf_soname(path):
    """The file's DT_SONAME, or None if it has none / is not an ELF.

    mkifs stores a shared object under its SONAME rather than under the name
    the entry gave it, so the harvester has to know the SONAME to describe
    what will actually land in the image -- see qnx_image_write_dropins.

    Read through the program headers rather than the section table: a stripped
    library may have no usable section headers, but PT_DYNAMIC is what the
    loader itself goes through and survives stripping."""
    import struct

    try:
        with open(path, 'rb') as f:
            if f.read(4) != b'\x7fELF':
                return None
            f.seek(0)
            data = f.read()
    except OSError:
        # A dangling symlink, or a directory. Not something to fail over here;
        # the caller just treats it as "no SONAME" and emits the entry as-is.
        return None

    if len(data) < 64:
        return None

    is64 = data[4] == 2
    endian = '<' if data[5] == 1 else '>'

    try:
        if is64:
            phoff = struct.unpack_from(endian + 'Q', data, 0x20)[0]
            phentsize, phnum = struct.unpack_from(endian + 'HH', data, 0x36)
        else:
            phoff = struct.unpack_from(endian + 'I', data, 0x1c)[0]
            phentsize, phnum = struct.unpack_from(endian + 'HH', data, 0x2a)

        # PT_LOAD segments are what let a virtual address (DT_STRTAB is one) be
        # turned back into a file offset.
        loads = []
        dynamic = None
        for i in range(phnum):
            off = phoff + i * phentsize
            if off + phentsize > len(data):
                return None
            p_type = struct.unpack_from(endian + 'I', data, off)[0]
            if is64:
                p_offset, p_vaddr = struct.unpack_from(endian + 'QQ', data, off + 8)
                p_filesz = struct.unpack_from(endian + 'Q', data, off + 32)[0]
            else:
                p_offset, p_vaddr = struct.unpack_from(endian + 'II', data, off + 4)
                p_filesz = struct.unpack_from(endian + 'I', data, off + 16)[0]
            if p_type == 1:      # PT_LOAD
                loads.append((p_vaddr, p_filesz, p_offset))
            elif p_type == 2:    # PT_DYNAMIC
                dynamic = (p_offset, p_filesz)

        # No .dynamic at all: a static binary or an object file. Not an error.
        if dynamic is None:
            return None

        soname_off = None
        strtab_vaddr = None
        entsize = 16 if is64 else 8
        fmt = endian + ('QQ' if is64 else 'II')
        pos = dynamic[0]
        end = min(dynamic[0] + dynamic[1], len(data))
        while pos + entsize <= end:
            d_tag, d_val = struct.unpack_from(fmt, data, pos)
            pos += entsize
            if d_tag == 0:       # DT_NULL, end of the array
                break
            elif d_tag == 14:    # DT_SONAME, offset into the string table
                soname_off = d_val
            elif d_tag == 5:     # DT_STRTAB, address of the string table
                strtab_vaddr = d_val

        # An executable, or a library linked without -soname. Both are normal.
        if soname_off is None or strtab_vaddr is None:
            return None

        base = None
        for p_vaddr, p_filesz, p_offset in loads:
            if p_vaddr <= strtab_vaddr < p_vaddr + p_filesz:
                base = strtab_vaddr - p_vaddr + p_offset
                break
        if base is None:
            return None

        start = base + soname_off
        stop = data.find(b'\x00', start)
        if start >= len(data) or stop < 0:
            return None
        return data[start:stop].decode('utf-8', 'replace') or None
    except (struct.error, IndexError):
        # A malformed or truncated ELF is the ELF check's business, not this
        # function's. Fall back to naming the entry after the file.
        return None


def qnx_image_harvest_roots(d):
    """(absolute directory, path prefix) pairs to walk under ${D}.

    The prefix is what the walk's relative paths are joined onto to form the
    image path, and it is empty for every current caller: a stage-tree recipe
    harvests ${D}/qnx-stage/aarch64le and wants /bin/foo, and a stock recipe
    harvests ${D} and wants /usr/bin/foo. It exists so a future layout that
    installs into a subdirectory but wants a different image path has somewhere
    to say so, rather than needing a second harvester."""
    import os

    destdir = d.getVar('D')
    dirs = (d.getVar('QNX_IMAGE_HARVEST_DIRS') or '').split() or ['']
    return [(os.path.normpath(destdir + '/' + sub), '') for sub in dirs]


python qnx_image_write_dropins() {
    """Write this recipe's .files and .startup fragments into the stage tree."""
    import os

    pn = d.getVar('PN')
    destdir = d.getVar('D')

    attr_map = qnx_ifs_flags(d, 'QNX_IFS_ATTR')
    dest_map = qnx_ifs_flags(d, 'QNX_IFS_DEST')
    default_attr = (d.getVar('QNX_IFS_DEFAULT_ATTR') or '').strip()
    used_attrs = set()
    used_dests = set()

    def record(key, ifs_dest, source, extra_attr=''):
        """One mkifs record: [attributes] destination=source.

        `key` is the installed file's basename. bitbake varflag names may only
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

    if d.getVar('QNX_IFS_AUTO_ENTRIES') == '1':
        style = (d.getVar('QNX_IMAGE_SOURCE_STYLE') or 'sysroot').strip()
        if style not in ('search', 'sysroot'):
            bb.fatal("%s: QNX_IMAGE_SOURCE_STYLE must be 'search' or 'sysroot', "
                     "got '%s'" % (pn, style))
        source_prefix = d.getVar('QNX_IMAGE_SOURCE_PREFIX') or ''

        searchable = (d.getVar('QNX_IFS_SEARCHABLE_DIRS') or '').split()
        excluded = (d.getVar('QNX_IFS_EXCLUDE_DIRS') or '').split()
        excl_suffix = tuple((d.getVar('QNX_IFS_EXCLUDE_SUFFIXES') or '').split())

        # The stage tree is never image content -- it is where these very
        # fragments are being written. This matters for a recipe harvesting ${D}
        # as a whole (a stock one, via qnx-toolchain): without it the .files
        # fragment would list itself. It is a no-op for a stage-tree recipe,
        # whose harvest root is already inside it.
        excluded.append((d.getVar('QNX_STAGE_DIR') or '').strip('/'))

        for root, prefix in qnx_image_harvest_roots(d):
            if not os.path.isdir(root):
                continue

            for dirpath, _, filenames in os.walk(root):
                reldir = os.path.relpath(dirpath, root)
                reldir = '' if reldir == '.' else reldir
                imagedir = os.path.join(prefix, reldir).strip('/')

                # Build inputs for other recipes, not image content.
                if any(imagedir == x or imagedir.startswith(x + '/')
                       for x in excluded):
                    continue

                for name in sorted(filenames):
                    if name.endswith(excl_suffix):
                        continue

                    ifs_dest = '/%s' % os.path.join(imagedir, name).lstrip('/')
                    full = os.path.join(dirpath, name)

                    if os.path.islink(full):
                        # Versioned shared libraries install as a chain --
                        # libfoo.so -> libfoo.so.1 -> libfoo.so.1.2.3. Emitting
                        # a symlink as a plain entry would silently duplicate
                        # the payload once per name.
                        target = os.readlink(full)

                        # ...but the chain cannot be mirrored literally, because
                        # the real file does not keep the name it was given (see
                        # below): it arrives as libfoo.so.1, so a link pointing
                        # at libfoo.so.1.2.3 would dangle. Aim every link at the
                        # SONAME instead, keeping any directory part of the
                        # original target.
                        soname = qnx_elf_soname(os.path.realpath(full))
                        if soname:
                            targetdir = os.path.dirname(target)
                            # The link that already carries the SONAME is the
                            # name the real file lands under, so emitting it
                            # would produce a link and a file of the same name.
                            # The real record covers it.
                            if not targetdir and name == soname:
                                continue
                            target = os.path.join(targetdir, soname)

                        entries.append(record(name, ifs_dest, target,
                                              extra_attr='type=link'))
                        continue

                    if style == 'sysroot':
                        # An absolute path into the installing image's sysroot.
                        # No search path is involved, so any location works --
                        # which is the whole point for a stock recipe.
                        source = source_prefix + ifs_dest
                    elif imagedir in searchable:
                        # e.g. aarch64le/bin/qnx-hello  ->  /bin/qnx-hello=qnx-hello
                        source = name
                    else:
                        bb.warn("%s: %s/%s is outside the mkifs search path (%s). "
                                "It will not be added to images automatically; add "
                                "an explicit entry via QNX_IFS_EXTRA_ENTRIES."
                                % (pn, imagedir or '.', name, ' '.join(searchable)))
                        continue

                    # mkifs files a shared object under its DT_SONAME and
                    # ignores the name the record gave it, so libfoo.so.1.2.3
                    # becomes libfoo.so.1 in the image whatever we ask for.
                    # Name it that way here too, so the .build file describes
                    # the image that is actually built and the links above have
                    # something real to point at. The source keeps the on-disk
                    # filename -- that is the file mkifs has to find.
                    soname = qnx_elf_soname(full)
                    if soname and soname != name:
                        ifs_dest = '/%s' % os.path.join(imagedir,
                                                        soname).lstrip('/')

                    entries.append(record(name, ifs_dest, source))

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
            bb.warn("%s: QNX_IFS_ATTR[%s] matched no installed file. Expected a "
                    "basename, e.g. the name as installed into "
                    "${QNX_STAGE_BINDIR}." % (pn, key))
    for key in sorted(set(dest_map) - used_dests):
        if dest_map[key].strip():
            bb.warn("%s: QNX_IFS_DEST[%s] matched no installed file. Expected a "
                    "basename, e.g. the name as installed into "
                    "${QNX_STAGE_BINDIR}." % (pn, key))

    dropin_dir = destdir + d.getVar('QNX_IFS_DROPIN_DIR')

    # A recipe that stages files for a template to name, and contributes no
    # records of its own, says so here. An image cannot read another recipe's
    # variables -- the same reason .startup carries its dependency list in a
    # header -- so this travels as a file like everything else.
    #
    # Without it, "contributes nothing to the image" fires on every BSP: true as
    # stated, and wrong as advice, since naming those binaries is the image's
    # job by design.
    if oe.types.boolean(d.getVar('QNX_IFS_STAGE_ONLY') or '0'):
        bb.utils.mkdirhier(dropin_dir)
        with open(os.path.join(dropin_dir, pn + '.stageonly'), 'w') as f:
            f.write('### %s stages files for an image to name; no records\n' % pn)

    if entries or extra:
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
        after = (d.getVar('QNX_IFS_STARTUP_AFTER') or '').split()

        timeout = (d.getVar('QNX_IFS_STARTUP_WAITFOR_TIMEOUT') or '5').strip()

        bb.utils.mkdirhier(dropin_dir)
        with open(os.path.join(dropin_dir, pn + '.startup'), 'w') as f:
            # The header carries the dependency list to the image recipe, which
            # cannot read another recipe's variables.
            f.write('### %s after=%s\n' % (pn, ','.join(after)))
            f.write(startup + '\n')
            for path in waitfor:
                f.write('waitfor %s %s\n' % (path, timeout))
}

# Without these, editing any of the drop-in inputs would not invalidate
# do_install, and the change would silently not reach the image.
qnx_image_write_dropins[vardeps] += "QNX_IFS_AUTO_ENTRIES QNX_IFS_STAGE_ONLY \
                                     QNX_IFS_STARTUP_CMD \
                                     QNX_IFS_EXTRA_ENTRIES QNX_IFS_SEARCHABLE_DIRS \
                                     QNX_IFS_STARTUP_AFTER QNX_IFS_STARTUP_WAITFOR \
                                     QNX_IFS_STARTUP_WAITFOR_TIMEOUT \
                                     QNX_IFS_DEFAULT_ATTR QNX_IFS_EXCLUDE_DIRS \
                                     QNX_IFS_EXCLUDE_SUFFIXES \
                                     QNX_IMAGE_HARVEST_DIRS QNX_IMAGE_SOURCE_STYLE \
                                     QNX_IMAGE_SOURCE_PREFIX \
                                     QNX_IFS_ATTR_SIG QNX_IFS_DEST_SIG"


python qnx_image_check_elfs() {
    import os
    import struct

    if d.getVar('QNX_ELF_CHECK') != '1':
        return

    destdir = d.getVar('D')
    want = int(d.getVar('QNX_ELF_MACHINE'))
    bad = []

    for sub in ((d.getVar('QNX_ELF_CHECK_DIRS') or '').split() or ['']):
        root = os.path.normpath(destdir + '/' + sub)
        if not os.path.isdir(root):
            continue

        for dirpath, _, filenames in os.walk(root):
            for name in filenames:
                path = os.path.join(dirpath, name)
                if os.path.islink(path) or not os.path.isfile(path):
                    continue
                with open(path, 'rb') as f:
                    head = f.read(20)
                # Only ELF files are checked. Scripts, config files and .a
                # archives (which start "!<arch>", not the ELF magic) pass
                # through untouched.
                if len(head) < 20 or head[:4] != b'\x7fELF':
                    continue
                endian = '<H' if head[5] == 1 else '>H'
                machine = struct.unpack_from(endian, head, 18)[0]
                if machine != want:
                    bad.append('%s (e_machine %d)'
                               % (os.path.relpath(path, destdir), machine))

    if bad:
        bb.fatal("%s installed ELF files that are not %s binaries -- the build "
                 "system probably ignored ${CC} and used the host compiler:\n  %s"
                 % (d.getVar('PN'), d.getVar('QNX_PROCESSOR'),
                    '\n  '.join(sorted(bad))))
}
qnx_image_check_elfs[vardeps] += "QNX_ELF_CHECK QNX_ELF_MACHINE QNX_ELF_CHECK_DIRS"

# NOTE: the two functions above are deliberately NOT added to do_install's
# postfuncs here. qnx-toolchain.bbclass is applied through INHERIT, which is
# global -- every class it pulls in reaches native and cross recipes too, and a
# postfunc added at class level would run on all of them. Each consumer adds
# them itself, where it already knows it is looking at a QNX target recipe.
