# qnx-toolchain.bbclass -- make qcc the default toolchain for TARGET recipes.
#
# This is the piece that lets a *stock* recipe from a normal Yocto layer build
# for QNX with no bespoke qnx-* wrapper. Where qnx-sdp.bbclass is inherited by
# hand by our own recipes, this class is applied globally (INHERIT) so it reaches
# every target recipe, including ones from meta-openembedded and friends.
#
# It only ever touches TARGET recipes -- the anonymous function below returns
# early for anything else -- so the native, nativesdk and cross recipes a build
# needs (cmake-native, autoconf-native, gcc-cross for those) keep their normal
# host toolchain untouched.
#
# The insight that makes it possible: qcc is a self-contained sysroot. A stock
# recipe compiling #include <stdio.h> finds QNX's headers and libc through qcc's
# own built-in paths, so no OE glibc/gcc-cross has to be built or staged. What a
# recipe still needs from OE is only the output of its *own* DEPENDS, which is
# added as ordinary -I/-L into the recipe sysroot.
#
# Building is only half of it. A recipe that builds but cannot be put in an
# image is of limited use, so this class also gives stock recipes the same
# image contract our own recipes have (qnx-image-contract.bbclass): after
# do_install they write an ifs.d drop-in describing what they installed, and
# their binaries are staged into the sysroot where an image can reach them. The
# result is that
#
#     QNX_IFS_INSTALL = "bzip2"
#
# in an image recipe works exactly as it does for a recipe written here.
#
# Scope, honestly: this gets portable code (the bulk of meta-oe libraries) to
# build. Code that assumes Linux/glibc still needs the same porting a hand build
# would -- the class removes the toolchain wall, not the portability work.

inherit qnx-image-contract

# SDP location -- same defaults as qnx-sdp, both fed from conf/layer.conf.
QNX_HOST ?= "${QNX_SDP_ROOT}/host/linux/x86_64"
QNX_TARGET ?= "${QNX_SDP_ROOT}/target/qnx"
QNX_CONFIGURATION ?= "${HOME}/.qnx"
QNX_CONFIGURATION_EXCLUSIVE ?= "${QNX_CONFIGURATION}"

# Harmless to export unconditionally: a native task never puts qcc on PATH (that
# is done only for target recipes below) and never reads these.
export QNX_HOST
export QNX_TARGET
export QNX_CONFIGURATION
export QNX_CONFIGURATION_EXCLUSIVE

QNX_VARIANT ?= "gcc_ntoaarch64le"
QNX_TOOL_PREFIX ?= "aarch64-unknown-nto-qnx8.0.0-"

# The dependency headers/libraries a recipe's own DEPENDS staged, in the standard
# recipe sysroot (/usr/...). qcc finds libc itself; --sysroot is deliberately not
# used, as it would replace qcc's QNX sysroot and break libc.
QNX_TC_SYSROOT_CFLAGS = "-I${RECIPE_SYSROOT}${includedir}"
#
# -rpath-link is not redundant with -L. GNU ld searches -L for libraries named
# on the command line, but for the *transitive* ones -- a DT_NEEDED of a library
# being linked against -- it searches only DT_RUNPATH, -rpath-link and -rpath.
# On Linux OE gets this free from --sysroot, which is exactly what is cleared
# here so qcc keeps its own. Without it a two-level dependency fails at link
# time with "libfoo.so.N, needed by libbar.so, not found (try using -rpath or
# -rpath-link)" followed by a wall of undefined references from *inside* the
# library, which reads like the library is broken rather than merely unfound.
#
# Nothing one level deep shows this -- zlib, bzip2 and json-c never did. It
# takes a recipe linking against a staged library that itself links a staged
# library: qtdeclarative -> Qt6Gui -> freetype.
#
# -rpath-link affects link-time resolution only. It records nothing in the
# output, so no build path reaches the target, unlike -rpath.
QNX_TC_SYSROOT_LDFLAGS = "-L${RECIPE_SYSROOT}${libdir} -L${RECIPE_SYSROOT}${base_libdir} \
                          -Wl,-rpath-link,${RECIPE_SYSROOT}${libdir} \
                          -Wl,-rpath-link,${RECIPE_SYSROOT}${base_libdir}"
# RECIPE_SYSROOT is a per-recipe absolute path; keep it out of the task hash.
CFLAGS[vardepsexclude] += "QNX_TC_SYSROOT_CFLAGS"
CXXFLAGS[vardepsexclude] += "QNX_TC_SYSROOT_CFLAGS"
LDFLAGS[vardepsexclude] += "QNX_TC_SYSROOT_LDFLAGS"

# ---------------------------------------------------------------------------
# What a stock recipe stages, and why the default is not enough
# ---------------------------------------------------------------------------
# On Linux the sysroot only has to carry *build inputs* -- headers and
# libraries -- because runtime files reach an image through do_package and
# do_rootfs. That is why oe-core's SYSROOT_DIRS lists includedir and libdir but
# leaves bindir and sbindir to SYSROOT_DIRS_NATIVE.
#
# Here there is no packaging (do_package is noexec below) and no do_rootfs: an
# image is an IFS or a QNX6 filesystem assembled straight out of the sysroot, so
# the sysroot is the only endpoint there is. Without this, `bitbake bzip2`
# succeeds, libbz2.so appears -- and /usr/bin/bzip2 exists nowhere an image can
# see it, which is a confusing way to find out.
#
# localstatedir is deliberately absent: /var is runtime state, created on the
# target, not image content.
QNX_TC_SYSROOT_DIRS ?= "${bindir} ${sbindir} ${base_bindir} ${base_sbindir} \
                        ${libexecdir} ${sysconfdir} ${QNX_STAGE_DIR}"

# ---------------------------------------------------------------------------
# CMake
# ---------------------------------------------------------------------------
# Autotools asks the compiler what it is; CMake is *told*, and oe-core tells it
# Linux. cmake.bbclass derives CMAKE_SYSTEM_NAME from HOST_OS, which stays
# "linux" here (see the README note on the TARGET_OS wart), so without this a
# stock CMake recipe compiles its Linux code paths with qcc -- it builds, and is
# wrong. That never showed up on zlib or bzip2 because autotools probes instead.
#
# CMAKE_SYSTEM_NAME has no variable to override, but the toolchain file is
# written by a shell function, and appending to it is a supported pattern --
# oe-core's own cmake-qemu.bbclass does exactly this. Later set() wins, so the
# handful of lines below simply restate what the earlier ones got wrong.
#
# CMake knows QNX natively (Modules/Platform/QNX.cmake, Modules/Compiler/QCC*),
# which is what keeps this short:
#
#   - CMAKE_C_COMPILER_TARGET becomes `-V<variant>` via QCC's
#     CMAKE_C_COMPILE_OPTIONS_TARGET. That flag is otherwise *lost*: CC here is
#     "qcc -V<variant>", and cmake.bbclass's oecmake_map_compiler() keeps only
#     argv[0]. A CMake recipe would build for qcc's default target -- x86_64 --
#     while everything else in the image is aarch64.
#   - CMAKE_SYSROOT is safe to point at the SDP because QCC.cmake emits it as
#     -Wc,-isysroot, not --sysroot. Left alone it would be RECIPE_SYSROOT, which
#     has no libc in it.
#
# Deliberately not modelled beyond this: a recipe needing more (extra find
# roots, CMAKE_TRY_COMPILE_TARGET_TYPE) sets it in its own EXTRA_OECMAKE.
QNX_CMAKE_SYSTEM_VERSION ?= "800"
QNX_CMAKE_SYSTEM_PROCESSOR ?= "aarch64le"

# Empty except on QNX target recipes -- the anonymous function below sets it.
# The guard has to be inside the function body rather than an override on it,
# because this class is INHERITed globally and MACHINE is not an override.
QNX_CMAKE_SYSTEM_NAME ?= ""

# Same idea, for the shell functions further down that have nothing to do with
# CMake: empty everywhere except a QNX target recipe.
QNX_TC_ACTIVE ?= ""

cmake_do_generate_toolchain_file:append() {
	if [ -n "${QNX_CMAKE_SYSTEM_NAME}" ]; then
		cat >> ${WORKDIR}/toolchain.cmake <<EOF

# --- appended by qnx-toolchain.bbclass: this is a QNX target, not Linux ---
set( CMAKE_SYSTEM_NAME ${QNX_CMAKE_SYSTEM_NAME} )
set( CMAKE_SYSTEM_VERSION ${QNX_CMAKE_SYSTEM_VERSION} )
set( CMAKE_SYSTEM_PROCESSOR ${QNX_CMAKE_SYSTEM_PROCESSOR} )

# Restores the -V<variant> that oecmake_map_compiler() dropped from \$CC.
set( CMAKE_C_COMPILER_TARGET ${QNX_VARIANT} )
set( CMAKE_CXX_COMPILER_TARGET ${QNX_VARIANT} )

# The SDP, not RECIPE_SYSROOT. Passed as -Wc,-isysroot, by Compiler/QCC.cmake.
set( CMAKE_SYSROOT ${QNX_TARGET} )

# Keep the OE sysroot entries cmake.bbclass already put here (that is where a
# recipe's own DEPENDS land) and add the SDP for find_library/find_path.
list( APPEND CMAKE_FIND_ROOT_PATH ${QNX_TARGET} ${QNX_TARGET}/${QNX_CMAKE_SYSTEM_PROCESSOR} )

# Host tools -- qcc, ntoaarch64-ar -- are on PATH, not under a find root.
set( CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER )

# The sysroot -L and -rpath-link, put where CMake will actually use them.
# cmake.bbclass passes these as CMAKE_<LANG>_LINK_FLAGS, which CMake does not
# consume when linking targets -- it is not one of the variables that reach a
# link line. On Linux that goes unnoticed because --sysroot (cleared here, so
# qcc keeps its own) already carries the search path. The _INIT variants are
# the documented way to *add* to the linker flags rather than replace what the
# project computed for itself.
string( APPEND CMAKE_EXE_LINKER_FLAGS_INIT    " ${QNX_TC_SYSROOT_LDFLAGS}" )
string( APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${QNX_TC_SYSROOT_LDFLAGS}" )
string( APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " ${QNX_TC_SYSROOT_LDFLAGS}" )
EOF
	fi
}

# ---------------------------------------------------------------------------
# Multilib headers
# ---------------------------------------------------------------------------
# oe-core's oe_multilib_header() renames an installed header aside and puts a
# wrapper in its place that does `#include <bits/wordsize.h>` and dispatches on
# __WORDSIZE. That header is glibc's. QNX does not have it, and does not have
# multilib either -- one machine, one ABI -- so the wrapper is both broken and
# pointless here.
#
# The failure is remote from its cause, which is what makes it worth handling
# centrally: the recipe installing the header succeeds, and some *other* recipe
# fails much later with "fatal error: bits/wordsize.h: No such file or
# directory". freetype is how this surfaced, via qtbase.
#
# multilib_header.bbclass already returns early for musl and for
# native/nativesdk. QNX is the same case, so this adds one more early return.
# :prepend rather than redefining the function, because the class is inherited
# by the recipe -- i.e. after this one -- so a plain definition here would be
# overwritten by it.
oe_multilib_header:prepend() {
	if [ -n "${QNX_TC_ACTIVE}" ]; then
		return
	fi
}

# Everything conditional happens here rather than through `:class-target = ...`
# overrides: a self-referential override (keep the old value when inactive) sends
# bitbake into infinite recursion. An imperative pass is both clearer and safe.
python () {
    # Inert on any other machine, so the class is safe to INHERIT globally.
    if d.getVar('MACHINE') != 'qnx-aarch64le':
        return

    # Our own recipes inherit qnx-sdp, which already sets all of this (and adds
    # the staging contract). Doing it again would only duplicate flags.
    if bb.data.inherits_class('qnx-sdp', d):
        return

    # Target recipes only. native/nativesdk/cross must keep the host toolchain,
    # or cmake-native and friends would try to build themselves with qcc.
    if 'class-target' not in (d.getVar('OVERRIDES') or '').split(':'):
        return

    variant = d.getVar('QNX_VARIANT')
    prefix = d.getVar('QNX_TOOL_PREFIX')

    d.setVar('CC', 'qcc -V%s' % variant)
    d.setVar('CXX', 'q++ -V%s' % variant)
    d.setVar('CPP', 'qcc -V%s -E' % variant)
    # The *raw* GNU ld, not the qcc driver. libtool decides whether it can build
    # a shared library by grepping `$LD --help` for GNU-ld ELF target support;
    # qcc's --help does not look like ld's, so with LD=qcc libtool gives up and
    # builds static only. Actual linking still goes through $CC (qcc) -- libtool's
    # archive_cmds is "$CC -shared ..." -- so $LD here is only for that probe.
    d.setVar('LD', '%sld' % prefix)
    for var, tool in (('AR', 'ar'), ('NM', 'nm'), ('RANLIB', 'ranlib'),
                      ('STRIP', 'strip'), ('OBJCOPY', 'objcopy'),
                      ('OBJDUMP', 'objdump'), ('READELF', 'readelf')):
        d.setVar(var, prefix + tool)

    # Yocto's target flags carry --sysroot=, -fmacro-prefix-map, the armv8a
    # -march tuning and a pile of hardening options aimed at its own gcc; qcc
    # rejects several outright and the sysroot must not be used.
    for var in ('TARGET_CC_ARCH', 'TARGET_LD_ARCH', 'TARGET_CPPFLAGS',
                'TOOLCHAIN_OPTIONS', 'DEBUG_PREFIX_MAP',
                'SECURITY_CFLAGS', 'SECURITY_LDFLAGS'):
        d.setVar(var, '')

    # The base CFLAGS carry more than hardening: -pipe and the debug/optimisation
    # set (-feliminate-unused-debug-types, -fmacro-prefix-map, ...), several of
    # which qcc's cc1 rejects outright ("-pipe is valid for the driver but not
    # for C"). Replace them wholesale, exactly as qnx-sdp does, rather than trying
    # to subtract each offending flag. -O2 is all a normal build needs.
    d.setVar('CFLAGS', '-O2')
    d.setVar('CXXFLAGS', '-O2')
    d.setVar('LDFLAGS', '')

    d.appendVar('CFLAGS', ' ${QNX_TC_SYSROOT_CFLAGS}')
    d.appendVar('CXXFLAGS', ' ${QNX_TC_SYSROOT_CFLAGS}')
    d.appendVar('LDFLAGS', ' ${QNX_TC_SYSROOT_LDFLAGS}')

    # No OE cross-gcc / glibc: qcc brings its own. This is what stops a stock
    # recipe dragging in binutils-cross, gcc-cross and glibc for a target it
    # cannot use. The strip/populatesysroot inhibits stop staging.bbclass from
    # pulling target binutils back in (POPULATESYSROOTDEPS) and undoing it.
    d.setVar('INHIBIT_DEFAULT_DEPS', '1')
    d.setVar('INHIBIT_SYSROOT_STRIP', '1')
    d.setVar('INHIBIT_PACKAGE_STRIP', '1')
    d.setVar('POPULATESYSROOTDEPS', '')

    # qcc and the SDP host tools first, for the compile/configure tasks. Target
    # only -- a native task must keep the host compiler ahead of qcc.
    d.prependVar('PATH', '%s/usr/bin:%s/host/common/bin:'
                 % (d.getVar('QNX_HOST'), d.getVar('QNX_SDP_ROOT')))

    # libtool decides how to build a shared library by probing the "linker" for
    # GNU-ld-ness. OE sets LD=qcc, so libtool runs `qcc -v`, does not see
    # "GNU ld", concludes with_gnu_ld=no, and leaves archive_cmds empty -- it
    # then makes the .so symlink but never links the real object, and the build
    # fails at "cannot find libfoo.so". qcc's underlying linker *is* GNU ld
    # (aarch64-unknown-nto-qnx8.0.0-ld), so telling libtool so is truthful. This
    # is what makes a stock autotools library actually produce its shared object.
    d.appendVar('CACHED_CONFIGUREVARS', ' lt_cv_prog_gnu_ld=yes')

    # No packaging. A QNX image is an IFS (mkifs) or a QNX6 filesystem
    # (mkqnx6fsimg), never an .ipk/.rpm rootfs, so do_package produces nothing
    # useful here -- and its QA would reject QNX ELFs as foreign. The sysroot
    # (do_populate_sysroot) is the real endpoint: it is what a DEPENDS consumer
    # and the image classes read. noexec the packaging tasks so a plain
    # `bitbake <recipe>` completes at the sysroot instead of failing in QA.
    for task in ('do_package', 'do_package_qa', 'do_packagedata',
                 'do_package_write_ipk', 'do_package_write_rpm',
                 'do_package_write_deb', 'do_package_write_tar'):
        d.setVarFlag(task, 'noexec', '1')

    # ...which makes the sysroot the endpoint, so it has to carry the runtime
    # files too, not just the build inputs oe-core stages by default.
    d.appendVar('SYSROOT_DIRS', ' ${QNX_TC_SYSROOT_DIRS}')

    # Arms the toolchain-file append above. Setting it here rather than at class
    # level is what keeps cmake-native building for the host: the append runs for
    # every CMake recipe in the build, and does nothing unless this is set.
    d.setVar('QNX_CMAKE_SYSTEM_NAME', 'QNX')
    d.setVar('QNX_TC_ACTIVE', '1')

    # The image contract. A stock recipe installs to the ordinary FHS paths
    # (${bindir}, ${libdir}), which are not on any mkifs search path, so its
    # entries name their source by absolute path into the installing image's
    # sysroot -- that is what QNX_IMAGE_SOURCE_STYLE = "sysroot" means, and it
    # is the class default. Harvesting all of ${D} (the empty harvest dir) is
    # also the default; both are spelled out here because this is the place
    # someone will look to understand how bzip2 ends up in an IFS.
    #
    # These are added imperatively rather than at class level for the same
    # reason as everything else above: this class is applied through INHERIT,
    # which reaches every recipe in the build, and a native recipe must not
    # start writing QNX image fragments.
    d.setVar('QNX_IMAGE_HARVEST_DIRS', '')
    d.setVar('QNX_IMAGE_SOURCE_STYLE', 'sysroot')
    d.appendVarFlag('do_install', 'postfuncs',
                    ' qnx_image_write_dropins qnx_image_check_elfs')
}
