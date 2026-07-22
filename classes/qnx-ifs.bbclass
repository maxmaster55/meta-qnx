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

    content = content.replace('@QNX_IFS_FILES@', files)
    content = content.replace('@QNX_IFS_STARTUP@', startup)

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

	# -a<name>: name embedded in the image and used for the .sym files mkifs
	#           drops beside it (procnto-*.sym, startup-*.sym), which are what
	#           you feed gdb when debugging the image.
	mkifs -a${QNX_IFS_NAME} -r${QNX_IFS_ROOT} -v \
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
