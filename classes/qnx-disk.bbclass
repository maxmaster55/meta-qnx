# qnx-disk.bbclass -- assemble a flashable disk image from QNX partitions.
#
# Produces a single .img that can be written straight to an SD card or USB
# stick, using the SDP's own tools in the order a QNX BSP does by hand:
#
#   mkfatfsimg   <boot template>  -> a FAT partition holding the IFS and the
#                                    board's firmware/device tree
#   diskimage    <disk config>    -> an MBR image wrapping the boot partition
#                                    and an optional pre-built data partition
#
# The data partition, if any, is a bare QNX6 filesystem image built by a
# qnx-rootfs recipe and pointed at by QNX_DISK_DATA_IMG.  This class never
# builds a QNX6 filesystem itself -- that responsibility lives entirely in
# qnx-rootfs.bbclass, so there is exactly one code path for mkqnx6fsimg.
#
# Sizes may be given explicitly ("200M") or left to compute themselves ("auto"),
# which is the interesting part. A QNX BSP normally carries these numbers by
# hand -- the project this layer was written against has literal
# "***CYLINDERS MODIFIED BY BUILD" and "***SECTORS MODIFIED BY BUILD" comments
# marking the spots a script patches. Here the boot partition is measured from
# what actually goes into it, and the disk from the partition images that were
# actually produced.

inherit qnx-sdp deploy

DEPENDS += "${QNX_DISK_INSTALL}"

# Image recipes whose deployed .ifs files this disk needs. Their do_deploy must
# run first, so this is a task-level dependency as well as a build one.
QNX_DISK_INSTALL ?= ""

QNX_DISK_NAME ?= "${PN}"

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------
# Expanded exactly like IFS templates: any @VARIABLE@ comes from the datastore,
# plus the computed sizes below.
QNX_DISK_BOOT_TEMPLATE ?= "${S}/${QNX_DISK_NAME}-boot.build.in"
QNX_DISK_CFG_TEMPLATE ?= "${S}/${QNX_DISK_NAME}-disk.cfg.in"

# ---------------------------------------------------------------------------
# Sizes
# ---------------------------------------------------------------------------
# Each accepts a byte count with an optional K/M/G suffix, or "auto".
#
#   QNX_DISK_BOOT_SIZE   the FAT partition          -> @QNX_DISK_BOOT_SECTORS@
#   QNX_DISK_SIZE        the whole disk             -> @QNX_DISK_CYLINDERS@
#
# "auto" for the boot partition measures the files its build file references and
# adds QNX_DISK_SLACK_PERCENT. "auto" for the disk sums the partition images
# that were built, so it is exact rather than estimated.
QNX_DISK_BOOT_SIZE ?= "auto"
QNX_DISK_SIZE ?= "auto"

# Headroom added to an auto-sized boot partition, as a percentage plus a floor.
QNX_DISK_SLACK_PERCENT ?= "25"

# An auto-sized boot partition that does not fit is grown and retried, because
# the real overhead of a filesystem is not predictable from a byte count.
QNX_DISK_GROW_ATTEMPTS ?= "5"
QNX_DISK_GROW_FACTOR ?= "1.5"
QNX_DISK_BOOT_MIN ?= "32M"

# ---------------------------------------------------------------------------
# Data partition
# ---------------------------------------------------------------------------
# Path to a pre-built QNX6 filesystem image (produced by a qnx-rootfs recipe)
# that becomes the disk's data partition.  Leave empty for a boot-only disk.
# The recipe that sets this must also add a task dependency on the rootfs
# recipe's do_deploy so the image exists when this disk is compiled.
QNX_DISK_DATA_IMG ?= ""

# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------
# 64 * 32 * 512 = a 1 MiB cylinder, which makes the disk size land on whole
# megabytes and keeps partition starts aligned. Match these in the disk config
# template via @QNX_DISK_HEADS@ and friends.
QNX_DISK_HEADS ?= "64"
QNX_DISK_SECTORS_PER_TRACK ?= "32"
QNX_DISK_SECTOR_SIZE ?= "512"

# Space reserved before the first partition for the MBR and any IPL.
QNX_DISK_RESERVED ?= "1M"

B = "${WORKDIR}/build"

def qnx_disk_content_size(d, buildfile):
    """Estimate what a QNX build file will put into a filesystem image.

    Sums the host files it references (the right-hand side of `dest=source`)
    plus the length of any inline `= { ... }` bodies. Sources are resolved
    against the search roots, since a build file names most things by bare
    name. Anything that cannot be found is skipped: mkfatfsimg/mkqnx6fsimg will
    fail on it later with a better message than anything guessed here."""
    import os
    import re

    roots = (d.getVar('QNX_DISK_SEARCH_ROOTS') or '').split()
    total = 0

    with open(buildfile) as f:
        text = f.read()

    # Inline bodies: name = { ... }
    for body in re.findall(r'=\s*\{(.*?)\n\}', text, re.S):
        total += len(body)

    text = re.sub(r'=\s*\{.*?\n\}', '=', text, flags=re.S)

    for line in text.splitlines():
        line = line.split('#', 1)[0].strip()
        if not line or line.startswith('[') and '=' not in line:
            continue
        if '=' not in line:
            continue
        source = line.rsplit('=', 1)[1].strip()
        if not source or source.startswith('/dev'):
            continue

        for candidate in ([source] if os.path.isabs(source) else
                          [os.path.join(r, source) for r in roots]):
            if os.path.isfile(candidate):
                total += os.path.getsize(candidate)
                break
            if os.path.isdir(candidate):
                for dirpath, _, names in os.walk(candidate):
                    total += sum(os.path.getsize(os.path.join(dirpath, n))
                                 for n in names
                                 if os.path.isfile(os.path.join(dirpath, n)))
                break

    return total

# Where qnx_disk_content_size looks for bare source names.
QNX_DISK_SEARCH_ROOTS ?= "${B} ${DEPLOY_DIR_IMAGE}"

python do_generate_diskfiles() {
    import os
    import math

    bb.utils.mkdirhier(d.getVar('B'))

    sector_size = int(d.getVar('QNX_DISK_SECTOR_SIZE'))
    slack = 1.0 + int(d.getVar('QNX_DISK_SLACK_PERCENT')) / 100.0

    boot_template = d.getVar('QNX_DISK_BOOT_TEMPLATE')
    out = os.path.join(d.getVar('B'), 'boot.build')
    requested = (d.getVar('QNX_DISK_BOOT_SIZE') or 'auto').strip()

    probe = out + '.probe'
    with open(probe, 'w') as f:
        f.write(qnx_expand_template(d, boot_template, {
            'QNX_DISK_BOOT_SECTORS': '0',
        }))

    if requested == 'auto':
        content = qnx_disk_content_size(d, probe)
        wanted = max(int(content * slack),
                     qnx_parse_size(d.getVar('QNX_DISK_BOOT_MIN'), 'QNX_DISK_BOOT_MIN'))
        bb.note("boot.build: auto-sized from %d bytes of content to %d bytes"
                % (content, wanted))
    else:
        wanted = qnx_parse_size(requested, 'QNX_DISK_BOOT_SIZE')

    sectors = math.ceil(wanted / sector_size)

    with open(out, 'w') as f:
        f.write(qnx_expand_template(d, boot_template, {
            'QNX_DISK_BOOT_SECTORS': str(sectors),
        }))
    os.remove(probe)
}
addtask generate_diskfiles after do_configure before do_compile

# The generated build files, for `bitbake -c dumpbuild <image>` (qnx-sdp). Two
# of them, and only the first exists this early: disk.cfg is written by
# do_generate_diskcfg, which runs after the partitions are built because it
# needs their real sizes. Ordering here rather than after that task keeps
# dumpbuild cheap -- reading the boot partition's layout should not cost a
# multi-gigabyte disk build. Run it again after a full build to see both.
QNX_BUILDFILES = "${B}/boot.build ${B}/disk.cfg"
addtask dumpbuild after do_generate_diskfiles

python do_compile() {
    import os
    import subprocess
    import shutil

    b = d.getVar('B')
    env = qnx_sdp_task_env(d)
    attempts = int(d.getVar('QNX_DISK_GROW_ATTEMPTS') or '5')
    factor = float(d.getVar('QNX_DISK_GROW_FACTOR') or '1.5')

    boot_auto = (d.getVar('QNX_DISK_BOOT_SIZE') or 'auto').strip() == 'auto'
    qnx_build_fsimg(d, 'mkfatfsimg', os.path.join(b, 'boot.build'),
                    os.path.join(b, 'part-boot.img'), boot_auto, env,
                    attempts=attempts, factor=factor, cwd=b)

    data_img = (d.getVar('QNX_DISK_DATA_IMG') or '').strip()
    if data_img:
        if not os.path.isfile(data_img):
            bb.fatal("QNX_DISK_DATA_IMG points at %s, which does not exist. "
                     "Add a do_compile[depends] on the rootfs recipe's do_deploy."
                     % data_img)
        # cp --sparse=never, not shutil.copy2.
        #
        # mkqnx6fsimg already produces a sparse image -- an 8G guest rootfs
        # occupies about 485M on disk -- and copy2 materialises every hole,
        # turning that into a real 8G write here and another one in do_install
        # and a third in do_deploy. Preserving the holes is the difference
        # between a build that writes half a gigabyte and one that writes
        # fourteen, for byte-identical output.
        # Hardlink first: diskimage only reads part-data.img, and this is the
        # same filesystem, so copying 4.4 GB to produce an identical file was
        # 50s of pure I/O per build. Falls back to a sparse copy across
        # filesystems.
        part = os.path.join(b, 'part-data.img')
        if os.path.exists(part):
            os.unlink(part)
        try:
            os.link(data_img, part)
        except OSError:
            subprocess.run(['cp', '--sparse=always', data_img, part], check=True)
}

# ---------------------------------------------------------------------------
# Don't put the disk image in sstate
# ---------------------------------------------------------------------------
# A disk image is an output, not a shared build artifact. Nothing ever consumes
# it as an input to another recipe, so caching it buys one thing only -- not
# re-running diskimage -- and charges for it on every build that does run.
#
# Measured here: the qnx-host-disk sstate object is 780 MB and takes ~23s to
# compress, and the cache had several of them side by side, one per hash. That
# is a per-build tax proportional to the image size, which is exactly the thing
# that made a bigger guest rootfs hurt.
#
# poky does the same for the SDK, for the same reason:
#     SSTATE_SKIP_CREATION:task-populate-sdk = '1'
#
# The task still runs and still deploys; it just is not packaged afterwards.
SSTATE_SKIP_CREATION:task-deploy = "1"

# ---------------------------------------------------------------------------
# bmap
# ---------------------------------------------------------------------------
# bmaptool create reads the entire image, ~20s on this disk.
#
# On by default, because without the file `bmaptool copy` fails outright:
#
#     bmaptool: ERROR: bmap file not found, please, use --nobmap option
#
# Note what the map is for here, because it is not what it usually is. do_deploy
# builds it before the image goes sparse, so it covers the whole file and a
# flash writes every byte. It buys no flashing time at all -- it exists so that
# `bmaptool copy` keeps working, and so that the map can never disagree with
# the image about which bytes matter.
#
# Skipping holes is not safe for this image. Its zeros are not all free space:
# some are padding inside the guest IFS, and a flash that skips those leaves
# whatever the card held before, which boots as far as a corrupt IFS gets.
#
# Set to "0" if you flash with dd and want the twenty seconds back.
QNX_DISK_BMAP ?= "1"

# Ship part-boot.img / part-data.img alongside the disk. Off: they are
# intermediates and part-data.img duplicates qnx-host-data.img.
QNX_DISK_DEPLOY_PARTS ?= "0"

python do_generate_diskcfg() {
    import os
    import math

    b = d.getVar('B')
    cylinder = (int(d.getVar('QNX_DISK_HEADS')) *
                int(d.getVar('QNX_DISK_SECTORS_PER_TRACK')) *
                int(d.getVar('QNX_DISK_SECTOR_SIZE')))

    partitions = [p for p in ('part-boot.img', 'part-data.img')
                  if os.path.isfile(os.path.join(b, p))]
    reserved = qnx_parse_size(d.getVar('QNX_DISK_RESERVED'), 'QNX_DISK_RESERVED')

    part_cylinders = [math.ceil(os.path.getsize(os.path.join(b, p)) / cylinder)
                      for p in partitions]
    used_cylinders = math.ceil(reserved / cylinder) + sum(part_cylinders)
    used = used_cylinders * cylinder

    requested = (d.getVar('QNX_DISK_SIZE') or 'auto').strip()
    if requested == 'auto':
        cylinders = used_cylinders
    else:
        total = qnx_parse_size(requested, 'QNX_DISK_SIZE')
        if total < used:
            bb.fatal("QNX_DISK_SIZE is %s but the partitions need %.1f MiB "
                     "(cylinder-aligned). Either raise it or set it to 'auto'."
                     % (requested, used / 1024.0 / 1024.0))
        cylinders = math.ceil(total / cylinder)

    with open(os.path.join(b, 'disk.cfg'), 'w') as f:
        f.write(qnx_expand_template(d, d.getVar('QNX_DISK_CFG_TEMPLATE'),
                                    {'QNX_DISK_CYLINDERS': str(cylinders)}))

    bb.note("disk: %d cylinders (%d MiB) for %d partition(s) totalling %.1f MiB"
            % (cylinders, cylinders * cylinder // 1024 // 1024,
               len(partitions), used / 1024.0 / 1024.0))
}
addtask generate_diskcfg after do_compile before do_install

do_install() {
	cd ${B}
	diskimage -o ${B}/${QNX_DISK_NAME}.img -c ${B}/disk.cfg

	# Do NOT punch the zero ranges out of this file.
	#
	# `fallocate --dig-holes` was here, to stop the image occupying its own
	# zeros. It reclaimed 10.7 GB and it produced cards that would not boot.
	#
	# dig-holes punches *any* aligned run of zeros, and it cannot tell free
	# filesystem space from zero padding inside a file. It put 15 holes inside
	# the embedded guest IFS alone. bmaptool then skips every hole -- it writes
	# only mapped ranges and never zeroes the rest -- so flashing onto a card
	# that already held an image left the previous card's bytes in all 15 gaps.
	# The result is an IFS of the right size, spliced from two builds, that
	# fails to boot in a way that looks exactly like a stale image.
	#
	# The image is a filesystem, so its zeros are content. Keep it allocated
	# and let the bmap in do_deploy describe the whole thing.
}

do_deploy() {
	install -d ${DEPLOYDIR}

	# Hardlink, do not copy.
	#
	# ${B} and ${DEPLOYDIR} are both under tmp/, so this is a directory entry
	# rather than 2.5 GB of I/O. Measured: this task took 119s copying, which
	# was the single largest cost in the whole image build -- larger than
	# actually assembling the disk.
	#
	# Safe because nothing rewrites the image in place after do_install; the
	# next build replaces the file rather than editing it. cp falls back to a
	# sparse copy if the link cannot be made (different filesystem).
	ln -f ${B}/${QNX_DISK_NAME}.img ${DEPLOYDIR}/${QNX_DISK_NAME}.img 2>/dev/null || \
		cp --sparse=never ${B}/${QNX_DISK_NAME}.img ${DEPLOYDIR}/
	chmod 0644 ${DEPLOYDIR}/${QNX_DISK_NAME}.img

	# The small text artifacts are always worth having.
	for f in ${B}/boot.build ${B}/disk.cfg; do
		[ -e "$f" ] || continue
		install -m 0644 "$f" ${DEPLOYDIR}/
	done

	# part-*.img are build intermediates, and part-data.img is a byte-for-byte
	# duplicate of qnx-host-data.img which its own recipe already deploys. They
	# were costing a gigabyte of copying per build to ship a second copy of
	# something already there. Set QNX_DISK_DEPLOY_PARTS = "1" to get them back
	# for debugging a partition layout.
	if [ "${QNX_DISK_DEPLOY_PARTS}" = "1" ]; then
		for f in ${B}/part-*.img; do
			[ -e "$f" ] || continue
			ln -f "$f" ${DEPLOYDIR}/$(basename "$f") 2>/dev/null || \
				cp --sparse=never "$f" ${DEPLOYDIR}/
		done
	fi

	# Map first, punch holes second. The order is the whole point.
	#
	# bmaptool create records which byte ranges to write; bmaptool copy then
	# reads those ranges out of the image and writes them. Ranges the map does
	# not list are never touched on the destination -- not written, not zeroed.
	#
	# So build the map while the image is still fully allocated and it covers
	# 100% of the file. Only then punch the zeros out. The file on disk drops
	# from 12 GB to about 1.2 GB, the content is unchanged (a hole reads back
	# as zeros), and the map still says "write all of it" -- so a flash writes
	# every byte, holes included, exactly as dd would.
	#
	# Punching first is what broke flashing: the map then omitted 10.7 GB,
	# including 15 ranges inside the guest IFS, and bmaptool copy left the
	# previous card's bytes in every one of them.
	if [ "${QNX_DISK_BMAP}" = "1" ] && command -v bmaptool >/dev/null 2>&1; then
		if ! bmaptool create -o ${DEPLOYDIR}/${QNX_DISK_NAME}.img.bmap \
				${B}/${QNX_DISK_NAME}.img; then
			bbwarn "bmaptool failed; the image is still usable, flashing it will just be slower"
			rm -f ${DEPLOYDIR}/${QNX_DISK_NAME}.img.bmap
		fi
	else
		bbnote "bmaptool not available; skipping block map"
	fi

	# Now the image may go sparse. Both paths are normally one inode; calling
	# it twice is harmless if the hardlink fell back to a copy.
	if command -v fallocate >/dev/null 2>&1; then
		before=$(du -m ${DEPLOYDIR}/${QNX_DISK_NAME}.img | cut -f1)
		fallocate --dig-holes ${B}/${QNX_DISK_NAME}.img 2>/dev/null || true
		fallocate --dig-holes ${DEPLOYDIR}/${QNX_DISK_NAME}.img 2>/dev/null || true
		after=$(du -m ${DEPLOYDIR}/${QNX_DISK_NAME}.img | cut -f1)
		bbnote "disk image: ${before} MiB -> ${after} MiB on disk (same content, and the bmap already covers the whole file)"
	fi
}
addtask deploy after do_install before do_build
