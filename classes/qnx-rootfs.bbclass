# qnx-rootfs.bbclass -- build a bare QNX6 filesystem image with mkqnx6fsimg.
#
# The single class for every QNX6 filesystem image, whether it is a guest's
# data disk (mounted with `mount -t qnx6 /dev/vblk0 /`) or a host disk's data
# partition (wrapped into an MBR by qnx-disk).  There is no MBR and no
# partition table here: the whole image *is* the filesystem.
#
# qnx-disk.bbclass points QNX_DISK_DATA_IMG at the deployed image from one of
# these recipes and wraps it into its disk layout, so every QNX6 filesystem
# goes through this class -- one code path for mkqnx6fsimg.
#
# A recipe lists what it carries, exactly like an image lists QNX_IFS_INSTALL:
#
#     QNX_ROOTFS_INSTALL = "qt-cluster qnx-screen-virtio"
#
# Those become DEPENDS, their staged files arrive in RECIPE_SYSROOT, and the
# template refers to them under @QNX_ROOTFS_SYSROOT@.

inherit qnx-sdp deploy

# Recipes whose staged files this image carries. Analogous to QNX_IFS_INSTALL.
QNX_ROOTFS_INSTALL ?= ""
DEPENDS += "${QNX_ROOTFS_INSTALL}"

QNX_ROOTFS_NAME ?= "${PN}"

# The mkqnx6fsimg build file: a template with @VARIABLE@ markers, expanded the
# same way IFS and disk templates are. Unlike an IFS there is no auto-derived
# file list -- a rootfs maps staged trees onto specific target paths that the
# guest's boot configuration depends on (LD_LIBRARY_PATH, screen's search dirs),
# so those mappings are stated in the template rather than guessed. This is why
# the project's own rootfs.build is written by hand too.
QNX_ROOTFS_TEMPLATE ?= "${S}/${QNX_ROOTFS_NAME}.build.in"
QNX_ROOTFS_BUILDFILE ?= "${B}/${QNX_ROOTFS_NAME}.build"
QNX_ROOTFS_IMG ?= "${B}/${QNX_ROOTFS_NAME}.img"

# The stage tree inside this recipe's sysroot. Exposed to the template as
# @QNX_ROOTFS_SYSROOT@, so it can name a staged tree by its stage path, e.g.
#     /qt-cluster = @QNX_ROOTFS_SYSROOT@/qt-cluster
QNX_ROOTFS_SYSROOT ?= "${RECIPE_SYSROOT}${QNX_STAGE_DIR}"

# The same sysroot at its root, for recipes that came from a normal Yocto layer:
# those install to the ordinary FHS paths rather than the stage tree, so a
# template puts one on the disk by its real path, e.g.
#     /usr/lib/libbz2.so.1.0.8 = @QNX_ROOTFS_OE_SYSROOT@/usr/lib/libbz2.so.1.0.8
# This is the data-disk counterpart of @QNX_IFS_SYSROOT@ in qnx-ifs.bbclass, and
# it is how a large payload from an external layer rides on the disk instead of
# being copied into guest RAM with the IFS.
QNX_ROOTFS_OE_SYSROOT ?= "${RECIPE_SYSROOT}"

# Size: "auto" starts at QNX_ROOTFS_MIN and grows until mkqnx6fsimg fits, since
# filesystem overhead is not predictable from content size. An explicit K/M/G
# size is used verbatim and never grows -- if you asked for 512M you want to be
# told it does not fit, not to silently get more.
QNX_ROOTFS_SIZE ?= "auto"
QNX_ROOTFS_MIN ?= "256M"
QNX_ROOTFS_GROW_ATTEMPTS ?= "6"
QNX_ROOTFS_GROW_FACTOR ?= "1.5"

# Inodes are preallocated at format time -- a hard ceiling on file count.
QNX_ROOTFS_INODES ?= "20000"
QNX_ROOTFS_BLKSIZE ?= "4096"

# Raw records for content with no staged file behind it. Newlines written as a
# literal \n (bitbake stores values literally, so there is otherwise no way to
# express a multi-line value). This is how a layer adds content to a rootfs
# defined elsewhere -- a guest layer appending its images, say -- without the
# rootfs recipe having to know about it.
QNX_ROOTFS_EXTRA ?= ""

B = "${WORKDIR}/build"

python do_generate_rootfs_buildfile() {
    import math
    import os

    bb.utils.mkdirhier(d.getVar('B'))

    template = d.getVar('QNX_ROOTFS_TEMPLATE')
    if not os.path.isfile(template):
        bb.fatal("mkqnx6fsimg template not found: %s" % template)

    requested = (d.getVar('QNX_ROOTFS_SIZE') or 'auto').strip()
    if requested == 'auto':
        wanted = qnx_parse_size(d.getVar('QNX_ROOTFS_MIN'), 'QNX_ROOTFS_MIN')
    else:
        wanted = qnx_parse_size(requested, 'QNX_ROOTFS_SIZE')

    # 512-byte sectors, rounded up to the multiple of 8 mkqnx6fsimg requires.
    sectors = math.ceil(wanted / 512)
    sectors += (-sectors) % 8

    extra = (d.getVar('QNX_ROOTFS_EXTRA') or '').replace('\\n', '\n').strip()

    content = qnx_expand_template(d, template, {
        'QNX_ROOTFS_SECTORS': str(sectors),
        'QNX_ROOTFS_EXTRA': extra,
    })
    with open(d.getVar('QNX_ROOTFS_BUILDFILE'), 'w') as f:
        f.write(content)

    bb.note("generated %s from %s (%d recipes installed)"
            % (d.getVar('QNX_ROOTFS_BUILDFILE'), template,
               len((d.getVar('QNX_ROOTFS_INSTALL') or '').split())))
}
addtask generate_rootfs_buildfile after do_configure before do_compile
do_generate_rootfs_buildfile[vardeps] += "QNX_ROOTFS_INSTALL QNX_ROOTFS_SIZE \
    QNX_ROOTFS_MIN QNX_ROOTFS_EXTRA QNX_ROOTFS_INODES QNX_ROOTFS_BLKSIZE"
do_generate_rootfs_buildfile[file-checksums] += "${@qnx_template_include_checksums(d)}"

# The generated build file, for `bitbake -c dumpbuild <image>` (qnx-sdp). This
# is where QNX_ROOTFS_EXTRA contributions from other layers become visible --
# the records are assembled at parse time and appear nowhere else.
QNX_BUILDFILES = "${QNX_ROOTFS_BUILDFILE}"
addtask dumpbuild after do_generate_rootfs_buildfile

python do_compile() {
    import os

    out = d.getVar('QNX_ROOTFS_IMG')
    auto = (d.getVar('QNX_ROOTFS_SIZE') or 'auto').strip() == 'auto'

    qnx_build_fsimg(d, 'mkqnx6fsimg',
                    d.getVar('QNX_ROOTFS_BUILDFILE'), out, auto,
                    qnx_sdp_task_env(d),
                    attempts=int(d.getVar('QNX_ROOTFS_GROW_ATTEMPTS')),
                    factor=float(d.getVar('QNX_ROOTFS_GROW_FACTOR')),
                    cwd=d.getVar('B'))

    bb.note("rootfs: %s built (%.1f MiB)"
            % (os.path.basename(out), os.path.getsize(out) / 1048576.0))
}

do_install[noexec] = "1"

# Same reasoning as qnx-disk.bbclass: a filesystem image is an output, and
# packaging one into sstate costs a compress of the whole thing on every build.
# qnx-host-data's object measured 369 MB. The task still runs and deploys.
SSTATE_SKIP_CREATION:task-deploy = "1"

do_deploy() {
	install -d ${DEPLOYDIR}
	# Hardlink rather than copy -- same filesystem, and this task measured 43s
	# copying an image that already exists two directories away. cp --sparse
	# is the fallback for a deploy dir on another filesystem.
	ln -f ${QNX_ROOTFS_IMG} ${DEPLOYDIR}/${QNX_ROOTFS_NAME}.img 2>/dev/null || \
		cp --sparse=always ${QNX_ROOTFS_IMG} ${DEPLOYDIR}/${QNX_ROOTFS_NAME}.img
	chmod 0644 ${DEPLOYDIR}/${QNX_ROOTFS_NAME}.img

	# The generated build file is deployed too: when the image is wrong, this is
	# what says what went into it.
	install -m 0644 ${QNX_ROOTFS_BUILDFILE} ${DEPLOYDIR}/${QNX_ROOTFS_NAME}.build
}
addtask deploy after do_compile before do_build
