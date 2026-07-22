# qnx-meson.bbclass -- build a meson project with the QNX SDP toolchain.
#
# Like qnx-cmake, this is deliberately not built on OE's meson.bbclass, which
# assumes Yocto's cross-toolchain, its sysroot layout, and native meson/ninja
# recipes -- all of which qnx-sdp.bbclass switches off.
#
# Two things a meson project on QNX needs that the SDP does not provide:
#
#   1. A cross file. Generated at ${QNX_MESON_CROSS} from the SDP paths, so it
#      never goes stale relative to QNX_SDP_ROOT (unlike a checked-in .ini with
#      absolute paths baked in).
#
#   2. pkg-config metadata for the SDP's own libraries. The SDP ships libdrm,
#      EGL, GLESv2 and gbm as plain .so files with no .pc, so any meson project
#      that does dependency('egl') fails to configure. QNX_MESON_SDP_PCFILES
#      synthesises them.
#
# Note the compilers here are the GNU-style drivers (ntoaarch64-gcc) rather than
# qcc. meson probes the compiler and does not understand qcc's -V argument, and
# this is what the project's own hand-written cross file uses.

inherit qnx-sdp

HOSTTOOLS += "meson ninja pkg-config"

B = "${WORKDIR}/build"

QNX_MESON_CROSS ?= "${B}/qnx-cross.ini"
QNX_MESON_STAGE ?= "${B}/meson-stage"

# Compiler names inside ${QNX_HOST}/usr/bin for this target.
QNX_MESON_CC ?= "ntoaarch64-gcc"
QNX_MESON_CXX ?= "ntoaarch64-g++"
QNX_MESON_AR ?= "ntoaarch64-ar"
QNX_MESON_STRIP ?= "ntoaarch64-strip"

QNX_MESON_SYSTEM ?= "qnx"
QNX_MESON_CPU_FAMILY ?= "aarch64"
QNX_MESON_CPU ?= "aarch64"
QNX_MESON_ENDIAN ?= "little"

# -include sys/neutrino.h and HAVE_TIMESPEC_GET mirror the project's own cross
# file: several of these libraries assume glibc-isms that QNX provides only once
# neutrino.h has been seen.
QNX_MESON_C_ARGS ?= "'-D_QNX_SOURCE', '-include', '${QNX_TARGET}/usr/include/sys/neutrino.h', '-DHAVE_TIMESPEC_GET=1'"
QNX_MESON_LINK_ARGS ?= ""

QNX_MESON_ARGS ?= ""

# SDP libraries to synthesise pkg-config files for, as
# "<name>:<version>:<link flags>[:<extra cflags>]".
QNX_MESON_SDP_PCFILES ?= "\
    libdrm:2.4.100:-ldrm:-I${QNX_TARGET}/usr/include/libdrm \
    egl:1.5:-lEGL \
    gl:1.0:-lGLESv2 \
    glesv2:3.2:-lGLESv2 \
    gbm:18.0.0:-lgbm \
"

python do_generate_meson_cross() {
    import os

    b = d.getVar('B')
    stage = d.getVar('QNX_MESON_STAGE')
    pkgconfig = os.path.join(stage, 'lib', 'pkgconfig')
    bb.utils.mkdirhier(pkgconfig)

    host = d.getVar('QNX_HOST')
    bindir = os.path.join(host, 'usr', 'bin')

    cross = """[binaries]
c = '%s'
cpp = '%s'
ar = '%s'
strip = '%s'
pkgconfig = 'pkg-config'

[built-in options]
c_args = [%s]
c_link_args = [%s]

[host_machine]
system = '%s'
cpu_family = '%s'
cpu = '%s'
endian = '%s'
""" % (os.path.join(bindir, d.getVar('QNX_MESON_CC')),
       os.path.join(bindir, d.getVar('QNX_MESON_CXX')),
       os.path.join(bindir, d.getVar('QNX_MESON_AR')),
       os.path.join(bindir, d.getVar('QNX_MESON_STRIP')),
       d.getVar('QNX_MESON_C_ARGS') or '',
       d.getVar('QNX_MESON_LINK_ARGS') or '',
       d.getVar('QNX_MESON_SYSTEM'), d.getVar('QNX_MESON_CPU_FAMILY'),
       d.getVar('QNX_MESON_CPU'), d.getVar('QNX_MESON_ENDIAN'))

    bb.utils.mkdirhier(b)
    with open(d.getVar('QNX_MESON_CROSS'), 'w') as f:
        f.write(cross)

    # pkg-config files for SDP libraries, which ship without any.
    target = d.getVar('QNX_TARGET')
    proc = d.getVar('QNX_PROCESSOR')
    for entry in (d.getVar('QNX_MESON_SDP_PCFILES') or '').split():
        parts = entry.split(':')
        if len(parts) < 3:
            bb.fatal("QNX_MESON_SDP_PCFILES entry '%s' should be "
                     "<name>:<version>:<libs>[:<cflags>]" % entry)
        name, version, libs = parts[0], parts[1], parts[2]
        extra = parts[3] if len(parts) > 3 else ''

        with open(os.path.join(pkgconfig, name + '.pc'), 'w') as f:
            f.write("prefix=%s/%s/usr\n" % (target, proc))
            f.write("exec_prefix=${prefix}\n")
            f.write("libdir=${exec_prefix}/lib\n")
            f.write("includedir=%s/usr/include\n" % target)
            f.write("\nName: %s\nDescription: %s (QNX SDP)\nVersion: %s\n"
                    % (name, name, version))
            f.write("Libs: -L${libdir} %s\n" % libs)
            f.write("Cflags: -I${includedir}%s\n" % (' ' + extra if extra else ''))

    # Libraries produced by other recipes are found through the same mechanism.
    sysroot_pc = d.getVar('RECIPE_SYSROOT') + d.getVar('QNX_STAGE_USRLIBDIR') + '/pkgconfig'
    d.setVar('QNX_MESON_PKG_CONFIG_LIBDIR', '%s:%s' % (pkgconfig, sysroot_pc))
}
addtask generate_meson_cross after do_patch before do_configure

export PKG_CONFIG_LIBDIR = "${QNX_MESON_STAGE}/lib/pkgconfig:${RECIPE_SYSROOT}${QNX_STAGE_USRLIBDIR}/pkgconfig"

do_configure() {
	meson setup ${B} ${S} --cross-file ${QNX_MESON_CROSS} \
		--default-library shared \
		--prefix ${QNX_STAGE_DIR} \
		--libdir ${QNX_PROCESSOR}/lib \
		--includedir usr/include \
		${QNX_MESON_ARGS}
}

do_compile() {
	ninja -C ${B} ${PARALLEL_MAKE}
}

do_install() {
	DESTDIR=${D} ninja -C ${B} install
}
