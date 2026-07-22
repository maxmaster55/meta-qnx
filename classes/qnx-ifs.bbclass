# qnx-ifs.bbclass -- assemble a QNX image filesystem (IFS) with mkifs.
#
# This is the Yocto equivalent of the images/ makefiles in a QNX BSP. The
# invocation mirrors qnx_guests/images/common.mk:
#
#     mkifs -a<name> -r<install-tree> -v <buildfile> <name>.ifs
#
# The interesting difference is dependency tracking. The makefile version has to
# scrape the .build file with grep/sed to discover which project files an image
# stages, so that a rebuilt app actually reaches the image. Here that is just
# DEPENDS: the app's staged files arrive in RECIPE_SYSROOT, and bitbake reruns
# do_mkifs when the app changes.

inherit qnx-sdp deploy

# mkifs reads $PROCESSOR to resolve unqualified binary names out of $QNX_TARGET
# (e.g. procnto-smp-instr, ksh, libc.so). The BSP makefiles export both of these.
export PROCESSOR = "${QNX_PROCESSOR}"
export ARCH = "${QNX_PROCESSOR}"

# Recipe-provided:
#   QNX_IFS_NAME      -- basename of the image, also passed to mkifs -a
#   QNX_IFS_BUILDFILE -- path to the .build file
QNX_IFS_NAME ?= "${PN}"
QNX_IFS_BUILDFILE ?= "${S}/${QNX_IFS_NAME}.build"

# Root prepended to mkifs's search path. Our staged apps live here, laid out to
# mirror $QNX_TARGET (see QNX_STAGE_DIR in qnx-sdp.bbclass), so a .build file can
# refer to them by bare name exactly as it refers to SDP binaries.
QNX_IFS_ROOT ?= "${RECIPE_SYSROOT}${QNX_STAGE_DIR}"

do_mkifs() {
	if [ ! -f "${QNX_IFS_BUILDFILE}" ]; then
		bbfatal "mkifs build file not found: ${QNX_IFS_BUILDFILE}"
	fi

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

	# Symbol files are optional (mkifs only writes them for images with a
	# startup/kernel) but are needed for source-level debugging when present.
	for sym in ${B}/*.sym; do
		[ -e "$sym" ] || continue
		install -m 0644 "$sym" ${DEPLOYDIR}/
	done
}
addtask deploy after do_mkifs before do_build
