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

python do_compile() {
    import os
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
        shutil.copy2(data_img, os.path.join(b, 'part-data.img'))
}

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
}

do_deploy() {
	install -d ${DEPLOYDIR}
	install -m 0644 ${B}/${QNX_DISK_NAME}.img ${DEPLOYDIR}/

	for f in ${B}/part-*.img ${B}/boot.build ${B}/disk.cfg; do
		[ -e "$f" ] || continue
		install -m 0644 "$f" ${DEPLOYDIR}/
	done

	if command -v bmaptool >/dev/null 2>&1; then
		if ! bmaptool create -o ${DEPLOYDIR}/${QNX_DISK_NAME}.img.bmap \
				${B}/${QNX_DISK_NAME}.img; then
			bbwarn "bmaptool failed; the image is still usable, flashing it will just be slower"
			rm -f ${DEPLOYDIR}/${QNX_DISK_NAME}.img.bmap
		fi
	else
		bbnote "bmaptool not available; skipping block map"
	fi
}
addtask deploy after do_install before do_build
