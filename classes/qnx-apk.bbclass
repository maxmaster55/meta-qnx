# qnx-apk.bbclass -- install a prebuilt package from QNX's OSS repository.
#
# QNX publishes open-source packages as .apk files at repo.oss.qnx.com. A recipe
# that wants one needs, in principle, only its name -- which is the recipe's own
# BPN -- so the minimum is:
#
#     inherit qnx-apk
#     SRC_URI[sha256sum] = "<sha256 of the .apk>"
#     LICENSE = "..."
#
# The version comes from PV (the recipe filename), the architecture from the
# machine, and the repository channel defaults below. A package in a different
# channel sets QNX_OSS_CHANNEL; the channels QNX serves are the ones the
# project's utils/download.mk lists (8.0.3/core, 8.0.3/extra, 8.0.4/qnx-core,
# 8.0.4/qnx-extra).
#
# The two things a recipe cannot avoid stating are the .apk's sha256 and its
# licence: both are per-package facts, and a binary package fetched without a
# checksum is neither reproducible nor safe. Everything mechanical is here.

inherit qnx-sdp

QNX_APK_NAME ?= "${BPN}"
QNX_APK_VERSION ?= "${PV}"

QNX_OSS_REPO ?= "https://repo.oss.qnx.com"
QNX_OSS_CHANNEL ?= "8.0.4/qnx-extra"
QNX_OSS_ARCH ?= "aarch64"

# unpack=0: an .apk is several concatenated streams -- an APKv2 signature, the
# control tarball, then the data tarball -- and bitbake's unpacker runs
# "xz -dc | tar", which fails on the first segment with "This does not look
# like a tar archive". `tar -xf` walks all of them, so extraction is done by
# hand in do_extract_apk below, exactly as the project's own download.mk does.
SRC_URI = "${QNX_OSS_REPO}/${QNX_OSS_CHANNEL}/${QNX_OSS_ARCH}/${QNX_APK_NAME}-${QNX_APK_VERSION}.apk;unpack=0"

QNX_APK_FILE = "${WORKDIR}/${QNX_APK_NAME}-${QNX_APK_VERSION}.apk"
S = "${WORKDIR}/${QNX_APK_NAME}-${QNX_APK_VERSION}"

# ---------------------------------------------------------------------------
# Licence
# ---------------------------------------------------------------------------
# A QNX apk carries no licence file, only a "license =" line in its .PKGINFO.
# That is the authoritative statement in the archive, so it is what
# LIC_FILES_CHKSUM points at by default. The md5 is per-package, so a recipe
# sets it -- either directly, or through QNX_APK_PKGINFO_MD5, which is the same
# thing spelled so the recipe does not have to repeat "file://.PKGINFO;md5=".
QNX_APK_PKGINFO_MD5 ?= ""
LIC_FILES_CHKSUM ?= "${@('file://.PKGINFO;md5=' + d.getVar('QNX_APK_PKGINFO_MD5')) if d.getVar('QNX_APK_PKGINFO_MD5') else ''}"

# Most of these packages are non-commercial (LicenseRef-QDL-Non-Commercial), so
# they are gated behind a licence flag by default: shipping one is then an
# explicit LICENSE_FLAGS_ACCEPTED decision rather than something that happens
# quietly. A recipe whose package is under different terms clears this.
LICENSE_FLAGS ?= "qnx-non-commercial"

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------
# A separate task, not an append to do_unpack: that one is a python task and a
# shell body cannot attach to it. Before do_patch, because do_populate_lic runs
# after do_patch and needs .PKGINFO already on disk.
do_extract_apk() {
	install -d ${S}
	# The "Ignoring unknown extended header keyword 'APK-TOOLS.checksum.SHA1'"
	# lines tar prints are expected: apk records a per-file checksum as a pax
	# header, which tar neither understands nor needs.
	tar -xf ${QNX_APK_FILE} -C ${S}
}
addtask extract_apk after do_unpack before do_patch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
# An apk is target-rooted: its usr/lib, lib, usr/bin and so on are the runtime
# paths, which map onto the stage tree's ${PROCESSOR}/ subtree (the mirror of
# $QNX_TARGET/${PROCESSOR}). The whole payload is copied there, minus the
# dotfile metadata (.PKGINFO, .SIGN.*, .BUILDINFO), which is not image content.
#
# A recipe needing a different layout -- headers into the sysroot include dir,
# say -- overrides do_install.
QNX_APK_DEST ?= "${QNX_STAGE_DIR}/${QNX_PROCESSOR}"

do_install() {
	install -d ${D}${QNX_APK_DEST}

	# cp -a to preserve the symlink chains a shared-library package ships;
	# the automatic IFS entry pass turns those into [type=link] records.
	found=0
	for entry in ${S}/*; do
		[ -e "$entry" ] || continue
		cp -a "$entry" ${D}${QNX_APK_DEST}/
		found=1
	done
	if [ "$found" = "0" ]; then
		bbfatal "${QNX_APK_NAME} apk unpacked to nothing -- has its layout changed?"
	fi
}
