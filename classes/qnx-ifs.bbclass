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
                        more nl seq sleep tee test true false yes clear"

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

# Additional roots, searched after the recipe sysroot and before $QNX_TARGET.
# mkifs accepts -r repeatedly and searches them left to right, which is what lets
# a board layer add a BSP install tree holding binaries the SDP does not ship --
# an RPi5 host image needs startup-bcm2712-rpi5, i2c-dwc-rpi5, gpio-rp1 and
# friends, none of which exist under $QNX_TARGET.
QNX_IFS_EXTRA_ROOTS ?= ""
QNX_IFS_ROOTS ?= "${QNX_IFS_ROOT} ${QNX_IFS_EXTRA_ROOTS}"

python do_generate_buildfile() {
    import os
    import re

    template = d.getVar('QNX_IFS_TEMPLATE')
    if not os.path.isfile(template):
        bb.fatal("mkifs template not found: %s" % template)

    # QNX_IFS_DROPIN_DIR is already rooted at QNX_STAGE_DIR, so it is joined to
    # RECIPE_SYSROOT -- not to QNX_IFS_ROOT, which would double the stage dir.
    dropin_dir = d.getVar('RECIPE_SYSROOT') + d.getVar('QNX_IFS_DROPIN_DIR')
    installed = (d.getVar('QNX_IFS_INSTALL') or '').split()

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
                    out.append((index, pn, f.read().rstrip('\n')))
        return out

    files = '\n'.join(text for _, _, text in read_dropins('.files'))

    # Startup fragments are ordered by priority, so a driver can be brought up
    # before the resource manager that needs it. The priority is carried in the
    # fragment's header line ("### <pn> prio=<n>") because the image recipe
    # cannot read another recipe's variables.
    #
    # Sorting on (priority, list index) makes the order of QNX_IFS_INSTALL the
    # tiebreak, so equal priorities stay predictable and controllable.
    def priority_of(pn, text):
        match = re.match(r'###\s+\S+\s+prio=(\d+)', text)
        if match:
            return int(match.group(1))
        bb.warn("%s: startup fragment from '%s' has no priority header; "
                "treating it as the default 500" % (d.getVar('PN'), pn))
        return 500

    fragments = read_dropins('.startup')
    fragments.sort(key=lambda item: (priority_of(item[1], item[2]), item[0]))
    startup = '\n'.join(text for _, _, text in fragments)

    # A recipe that stages nothing and starts nothing is almost certainly a
    # mistake -- a typo in QNX_IFS_INSTALL, or a recipe that never installed
    # into ${QNX_STAGE_DIR} -- and would otherwise produce a silently empty image.
    for pn in installed:
        if not any(os.path.isfile(os.path.join(dropin_dir, pn + s))
                   for s in ('.files', '.startup')):
            bb.warn("%s: '%s' is in QNX_IFS_INSTALL but contributes nothing to the "
                    "image. Does it install into ${QNX_STAGE_DIR} and inherit "
                    "qnx-sdp?" % (d.getVar('PN'), pn))

    with open(template) as f:
        content = f.read()

    if '@QNX_IFS_FILES@' not in content:
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
        lines = ['', '### toybox (multicall: one binary, %d commands)'
                 % len(toybox_cmds),
                 '%s=%s' % (toybox_path, toybox)]
        # Absolute link targets. The SDP docs show a bare "=toybox", but a
        # symlink target without a leading slash resolves relative to the link's
        # own directory -- /bin/ls would look for /bin/toybox, which is not
        # where it lives.
        lines += ['[type=link] /bin/%s=%s' % (cmd, toybox_path)
                  for cmd in toybox_cmds]
        files = files + '\n'.join(lines) + '\n'

    generated = {
        'QNX_IFS_FILES': files,
        'QNX_IFS_STARTUP': startup,
    }

    def expand(match):
        name = match.group(1)
        if name in generated:
            return generated[name]
        value = d.getVar(name)
        if value is None:
            bb.fatal("%s references @%s@, which is not set" % (template, name))
        return value

    content = re.sub(r'@([A-Z][A-Z0-9_]*)@', expand, content)

    buildfile = d.getVar('QNX_IFS_BUILDFILE')
    bb.utils.mkdirhier(os.path.dirname(buildfile))
    with open(buildfile, 'w') as f:
        f.write(content)

    bb.note("generated %s from %s (%d recipes installed)"
            % (buildfile, template, len(installed)))
}
addtask generate_buildfile after do_configure before do_mkifs
do_generate_buildfile[vardeps] += "QNX_IFS_INSTALL"

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
