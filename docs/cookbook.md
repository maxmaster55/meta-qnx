# Cookbook

Worked examples, roughly in order of increasing complexity. Every one of these is either a
real recipe in this layer or in `meta-qnx-hyp`.

> These are patterns for things you **build**. If what you need already exists — a QNX
> component, a board driver, or an open-source package QNX publishes — see
> [where-things-come-from.md](where-things-come-from.md) first; writing a recipe may not be
> the answer. For a narrative tour rather than a reference, see
> [showcase.md](showcase.md).

- [A hello-world application](#a-hello-world-application)
- [Adding it to an image](#adding-it-to-an-image)
- [An application with a makefile](#an-application-with-a-makefile)
- [An application fetched from git](#an-application-fetched-from-git)
- [A CMake application](#a-cmake-application)
- [A meson project](#a-meson-project)
- [A library reused from upstream (autotools)](#a-library-reused-from-upstream-autotools)
- [A library other recipes link against](#a-library-other-recipes-link-against)
- [A driver or resource manager](#a-driver-or-resource-manager)
- [Permissions and ownership](#permissions-and-ownership)
- [Symlinks](#symlinks)
- [Config files](#config-files)
- [Putting a file somewhere unusual](#putting-a-file-somewhere-unusual)
- [A new image](#a-new-image)
- [A board that needs binaries the SDP lacks](#a-board-that-needs-binaries-the-sdp-lacks)
- [A prebuilt QNX OSS package](#a-prebuilt-package-from-qnxs-oss-repository)
- [A flashable SD card image](#a-flashable-sd-card-image)
- [A data disk for payloads too big for an IFS](#a-data-disk-for-payloads-too-big-for-an-ifs)
- [Debugging what ended up in an image](#debugging-what-ended-up-in-an-image)

---

## A hello-world application

The minimum. Compile with `qcc`, install into the stage tree, done.

```bitbake
SUMMARY = "Hello world for QNX"
LICENSE = "CLOSED"

SRC_URI = "file://qnx-hello.c"

inherit qnx-sdp

# scarthgap has no UNPACKDIR (that arrived in styhead), so file:// sources are
# unpacked straight into WORKDIR.
S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} -o qnx-hello qnx-hello.c
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 qnx-hello ${D}${QNX_STAGE_BINDIR}/qnx-hello
}
```

Note what is **absent**: no path inside the image, no file list, no mention of a `.build`
file. The `/bin/qnx-hello` entry is derived from what `do_install` staged.

## Adding it to an image

One word:

```bitbake
QNX_IFS_INSTALL = "qnx-hello"
```

To also run it at boot, in the *application* recipe:

```bitbake
QNX_IFS_STARTUP_CMD = "qnx-hello"
```

## An application with a makefile

If the project already cross-compiles for QNX, drive it as-is.

```bitbake
inherit qnx-sdp

# Command-line variables beat the makefile's own assignments, which is what routes
# the build through the compiler this class configured.
EXTRA_OEMAKE = "CC='${CC}' CXX='${CXX}'"

do_compile() {
	oe_runmake -C ${S}
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 ${B}/shm_chunker ${D}${QNX_STAGE_BINDIR}/shm_chunker
}
```

> **Do not blindly pass `CFLAGS`.** Many QNX makefiles use simple assignment
> (`CFLAGS := -Vgcc_ntoaarch64le -std=gnu11 ...`), so overriding it from the command line
> discards the `-std` and `-V` flags along with everything else. Pass `CC`/`CXX` and leave
> `CFLAGS` alone unless you know the makefile appends rather than assigns.

## An application fetched from git

`qnx-src` handles the source side; combine it with whichever build class fits:

```bitbake
inherit qnx-sdp qnx-src

QNX_SRC_REPO = "git://github.com/you/thing.git;protocol=https;branch=main"
QNX_SRC_SUBDIR = "src/thing"        # optional, for a repo of many apps
```

By default this tracks the branch head — every build picks up the last push. Pin it for a
reproducible, offline build:

```bitbake
QNX_SRC_REV = "c19814a7c0b4a0c4b0e5e0e1f2a3b4c5d6e7f8a9"
```

To hack on the application without committing, point the recipe at a checkout — per-recipe
from `local.conf`:

```bitbake
QNX_SRC_LOCAL:pn-frame-router = "/path/to/checkout"
```

The tree is then built in place via `externalsrc` (no sstate, rebuilds every time — the
right default while editing). Real examples: `spi-loopback` and `rpi-gpio` in the project
layers fetch from GitHub; `frame-router` builds the monorepo working tree via
`QNX_PROJECT_SRC`.

## A CMake application

```bitbake
inherit qnx-cmake

# ...and that may be all. If the project's install() rules already target
# ${CMAKE_SYSTEM_PROCESSOR}/sbin and usr/include -- the QNX convention -- they land
# correctly with no do_install here at all.
```

Real example: `rpi-gpio` in `meta-qnx-hyp` has **no install code**, because upstream
already does:

```cmake
install(TARGETS ${PROJECT_NAME} DESTINATION ${CMAKE_SYSTEM_PROCESSOR}/sbin)
install(FILES ${PUBLIC_HEADER} DESTINATION usr/include/sys)
```

which with the prefix set to the stage tree puts the binary in the image and the header in
the sysroot only.

If the project needs options:

```bitbake
OECMAKE_EXTRA_ARGS = "-DBUILD_TESTING=OFF -DUSE_FOO=ON"
OECMAKE_BUILD_TYPE = "Debug"
```

## A meson project

```bitbake
inherit qnx-meson

QNX_MESON_ARGS = "-Dtests=false"
```

The class generates a cross file from the SDP paths, so nothing checked in ever goes stale
relative to `QNX_SDP_ROOT`. Installs are already prefixed onto the stage tree.

Two QNX-specific problems it solves that are worth knowing about:

- **The SDP ships `libdrm`, `EGL`, `GLESv2` and `gbm` without pkg-config files**, so any
  `dependency('egl')` would fail to configure. The class synthesises `.pc` files for them;
  add more via `QNX_MESON_SDP_PCFILES = "... foo:1.0:-lfoo"`.
- **meson does not understand `qcc -V`**, so the compilers are the GNU-style drivers
  (`ntoaarch64-gcc`), exactly as a hand-written QNX cross file would use.

Real examples: `libepoxy` and `virglrenderer` in `meta-qnx-hyp`.

## A library reused from upstream (autotools)

Most of meta-openembedded and oe-core is `./configure` + `make`. `qnx-autotools` drives
that family, and a **portable** upstream library needs no patches — just the tarball:

```bitbake
inherit qnx-autotools

SRC_URI = "https://example.org/libfoo-${PV}.tar.gz"
SRC_URI[sha256sum] = "..."
S = "${WORKDIR}/libfoo-${PV}"

# For a real GNU autoconf project, that is usually all: the class passes
# --host=aarch64-unknown-nto-qnx8.0.0 (cross mode), the stage-tree install dirs,
# and --disable-static, then runs make + make install.
EXTRA_OECONF = "--without-tests"
```

Real example: `recipes-example/zlib` builds **unmodified upstream zlib** this way. zlib's
configure is hand-rolled rather than GNU autoconf, so it shows the escape hatches — a
configure that rejects the standard flags is steered with a few overrides:

```bitbake
QNX_CONFIGURE_HOST = ""                    # this configure ignores --host/--build
QNX_AUTOTOOLS_DIRS = "--libdir=${QNX_STAGE_LIBDIR} --includedir=${QNX_STAGE_INCLUDEDIR}"
DISABLE_STATIC = ""                        # ...and rejects --disable-static
EXTRA_OECONF = "--shared --uname=GNU"
```

It stages `libz.so*` into `${QNX_STAGE_LIBDIR}` and `zlib.h` into the sysroot, so
`recipes-example/qnx-zlib-user` links it with nothing but `DEPENDS = "zlib"` and `-lz` —
verified: the resulting binary's `NEEDED` list contains `libz.so.1`.

> **The class removes the toolchain, not the porting.** A library builds unpatched only if
> its *code* is portable. Something that reaches for a Linux `/proc` layout, a glibc-only
> extension or a Linux socket option still needs the same fixes a hand build would — the
> win is that you are not also fighting the toolchain.

## A library other recipes link against

Install the library into the stage lib dir and its headers into the stage include dir:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_LIBDIR} ${D}${QNX_STAGE_INCLUDEDIR}
	install -m 0644 libmine.so.1.0.0 ${D}${QNX_STAGE_LIBDIR}/
	ln -sf libmine.so.1.0.0 ${D}${QNX_STAGE_LIBDIR}/libmine.so.1
	ln -sf libmine.so.1      ${D}${QNX_STAGE_LIBDIR}/libmine.so
	install -m 0644 mine.h   ${D}${QNX_STAGE_INCLUDEDIR}/
}
```

The consumer needs one line:

```bitbake
DEPENDS = "libmine"
```

and gets `-I`/`-L` pointing at them automatically. The header goes to the sysroot only; the
`.so` chain enters images as one real file plus `[type=link]` entries, not three copies.

## A driver or resource manager

Declare what you need to run after, and make the ordering mean something:

```bitbake
QNX_IFS_STARTUP_CMD = "rpi_gpio &"
QNX_IFS_STARTUP_AFTER = ""
QNX_IFS_STARTUP_WAITFOR = "/dev/gpio"
```

`&` means the startup script continues the moment it forks — long before
`resmgr_attach()` has registered the device. `AFTER` orders the commands;
`waitfor` is what actually blocks until the node exists. Use both.

An application that depends on the driver declares it:

```bitbake
QNX_IFS_STARTUP_CMD = "my-app"
QNX_IFS_STARTUP_AFTER = "rpi-gpio"
```

Generated result (order derived from the dependency graph):

```text
### rpi-gpio after=
rpi_gpio &
waitfor /dev/gpio 5
### my-app after=rpi-gpio
my-app
```

## Permissions and ownership

```bitbake
QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"     # setuid root
QNX_IFS_DEFAULT_ATTR   = "uid=0 gid=0"                # all of this recipe's entries
```

Any mkifs record attribute works — the value is passed through verbatim:

```bitbake
QNX_IFS_ATTR[bigfile]   = "data=copy"      # copy rather than reference
QNX_IFS_ATTR[secret.so] = "perms=0400"
QNX_IFS_ATTR[fw.bin]    = "sha512"
```

Keys are **basenames**. `QNX_IFS_ATTR[/sbin/rpi_gpio]` is a parse error — bitbake varflag
names cannot contain `/`.

Verify with `dumpifs -v`:

```
sbin/rpi_gpio    gid=0 uid=0 mode=04755
```

## Symlinks

If you stage the target yourself, just make a real symlink — it is picked up automatically:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 myapp ${D}${QNX_STAGE_BINDIR}/myapp
	ln -sf myapp ${D}${QNX_STAGE_BINDIR}/myapp-alias
}
```

→ `[type=link] /bin/myapp-alias=myapp`

Use a **relative** target (`ln -sf myapp ...`), not `ln -sf ${QNX_STAGE_BINDIR}/myapp ...`,
which would bake a build-host path into the image.

If the target is not something you staged (`/tmp`, `/dev`, another recipe's file):

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[type=link] /var/log=/tmp"
```

Several entries need a literal `\n` — bitbake does not process escapes, and a line
continuation collapses to a space:

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[type=link] /var/log=/tmp\n[type=link] /etc/x=/tmp/x"
```

> Only symlinks to **files** are detected automatically. `os.walk` reports symlinked
> *directories* separately, so those need an explicit entry.

## Config files

Stage a real file and give it permissions:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR}/etc
	install -m 0644 myapp.conf ${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR}/etc/
}
```

`etc` is **not** on mkifs's search path, so this warns and you must place it explicitly:

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[perms=0644] /etc/myapp.conf=${WORKDIR}/myapp.conf"
```

Or write the body inline in the image template, which is what the project's own build files
do for small scripts:

```
[perms=0744] /proc/boot/.start.sh = {
#!/bin/ksh
echo hello
}
```

## Putting a file somewhere unusual

```bitbake
QNX_IFS_DEST[myapp] = "/proc/boot/myapp"
```

`/proc/boot` is useful for things the startup script runs before any filesystem is mounted.

## A new image

```bitbake
SUMMARY = "My QNX image"
LICENSE = "CLOSED"

SRC_URI = "file://my-image.build.in"

inherit qnx-ifs

S = "${WORKDIR}"
B = "${WORKDIR}/build"

QNX_IFS_NAME = "my-image"
QNX_IFS_TEMPLATE = "${S}/my-image.build.in"

QNX_IFS_INSTALL = "qnx-hello rpi-gpio"

do_configure[noexec] = "1"
do_compile[noexec] = "1"
```

Minimal template:

```
[-optional]
[+keeplinked]
[image=@QNX_IMAGE_ADDR@]

[virtual=@QNX_IMAGE_VIRTUAL@] boot = {
    @QNX_STARTUP@ @QNX_STARTUP_ARGS@
    PATH=@QNX_IFS_PATH@ LD_LIBRARY_PATH=@QNX_IFS_LD_LIBRARY_PATH@ @QNX_KERNEL@ @QNX_KERNEL_ARGS@
}

[+script] startup-script = {
    SYSNAME=nto
    procmgr_symlink ../../proc/boot/ldqnx-64.so.2 /usr/lib/ldqnx-64.so.2
    pipe
    slogger2

    devc-virtio 0x20000000,42
    waitfor /dev/vcon1 4
    reopen /dev/vcon1

@QNX_IFS_STARTUP@

    [+session] ksh &
}

[uid=0 gid=0]
[type=link] /bin/sh=/bin/ksh
[type=link] /tmp=/dev/shmem

@QNX_IFS_FILES@

/sbin/devc-virtio=devc-virtio
/bin/ksh=ksh
```

For a different boot environment — a hypervisor host rather than a guest — override the
boot variables in the recipe:

```bitbake
QNX_IMAGE_ADDR = "0x80000"
QNX_IMAGE_VIRTUAL = "${QNX_PROCESSOR},raw -compress"
QNX_STARTUP = "startup-bcm2712-rpi5"
QNX_STARTUP_ARGS = "-v -u reg -a -W 5000 -Q enable,el1-host"
```

The same template works for both.

## A board that needs binaries the SDP lacks

BSP drivers are often built outside the SDP. Add their install tree as another search root:

```bitbake
QNX_IFS_EXTRA_ROOTS = "${QNX_PROJECT_SRC}/qnx_host/install"
```

Roots are searched left to right, before `$QNX_TARGET`. The tree must mirror
`$QNX_TARGET`'s layout (`aarch64le/sbin/...`).

Nested directories need a subpath, because the search path is flat — `lib/dll` is searched,
`lib/dll/pci` is not:

```
/lib/dll/pci/pci_slog2.so=pci/pci_slog2.so
```

## A prebuilt package from QNX's OSS repository

QNX ships open-source packages as `.apk` files at repo.oss.qnx.com. `qnx-apk`
fetches, extracts and stages one from little more than its name:

```bitbake
SUMMARY = "..."
LICENSE = "LicenseRef-QDL-Non-Commercial"

inherit qnx-apk

SRC_URI[sha256sum] = "<sha256 of the .apk>"
```

That is the whole recipe. Name and version come from the filename, so the only
per-package facts are the licence and one checksum.

Name and version come from the recipe filename; the architecture from the
machine; the repository channel defaults to `8.0.4/qnx-extra` and is overridden
with `QNX_OSS_CHANNEL` for a package served elsewhere (`8.0.3/core`,
`8.0.3/extra`, `8.0.4/qnx-core`).

### Where the checksum comes from

You do not hunt for it. Write the recipe without the `SRC_URI[sha256sum]` line,
run `bitbake -c fetch <recipe>`, and bitbake downloads the `.apk`, hashes it, and
prints the exact line to paste:

```
ERROR: ... Missing SRC_URI checksum, please add those to the recipe:
SRC_URI[sha256sum] = "97938cf4fed1ca463c5dd50f533a0e4deeba110361666bfd35619a498326b6cc"
```

That is the standard OpenEmbedded loop for any new source, and it is the only
checksum this class needs.

> **Do not use the "Package Checksum" from the QNX Open-Source Dashboard.** That
> value is the package's `datahash` — the sha256 of the *uncompressed* payload —
> not the sha256 of the `.apk` file bitbake downloads. They are different by
> construction and it will not verify. Let bitbake print the right one.

The whole payload is staged under `${QNX_PROCESSOR}/`, mirroring where it lives
on the target; the `.PKGINFO`/`.SIGN`/`.BUILDINFO` metadata is left out. Override
`do_install` for a package that needs a different layout.

The licence needs no checksum. A QNX apk has no licence file, only a `license =`
line in its `.PKGINFO`, and that is already covered by the `.apk` sha256 -- so
the class drops the usual "no licence file" QA rather than making you dig an md5
out of the archive. Most of these packages are `LicenseRef-QDL-Non-Commercial`,
which `qnx-apk` gates behind a licence flag: accept it in `local.conf` with
`LICENSE_FLAGS_ACCEPTED += "qnx-non-commercial"`.

## A flashable SD card image

An IFS is not something you can write to a card. `qnx-disk` wraps it in a
partitioned disk:

```bitbake
inherit qnx-disk

S = "${WORKDIR}"
SRC_URI = "file://my-boot.build.in file://my-disk.cfg.in"

QNX_DISK_NAME = "my"

# The image whose .ifs goes on the boot partition.
QNX_DISK_INSTALL = "my-image"
do_generate_diskfiles[depends] += "my-image:do_deploy"

# If you have a data partition, point at a qnx-rootfs recipe's deployed image.
QNX_DISK_DATA_IMG = "${DEPLOY_DIR_IMAGE}/my-data.img"
do_compile[depends] += "my-data:do_deploy"
```

The boot template needs the size marker and the files the board's firmware wants:

```
[num_sectors=@QNX_DISK_BOOT_SECTORS@]

config.txt = {
arm_64bit=1
kernel=qnx_sdp.ifs
}

qnx_sdp.ifs = @DEPLOY_DIR_IMAGE@/my-image.ifs
```

Then:

```bash
bitbake my-disk
sudo bmaptool copy tmp/deploy/images/qnx-aarch64le/my.img /dev/sdX
```

Check it before flashing:

```bash
fdisk -l my.img      # bootable FAT32 partition + type-179 QNX6 partition
```

## A data disk for payloads too big for an IFS

An IFS is copied into RAM whole at boot, so a large runtime — Qt, a graphics stack —
cannot live in it. `qnx-rootfs` builds a bare QNX6 filesystem image that a guest mounts as
a disk instead. It carries recipes the same way an image does:

```bitbake
inherit qnx-rootfs

S = "${WORKDIR}"
SRC_URI = "file://rootfs.build.in"

QNX_ROOTFS_NAME = "rootfs"
QNX_ROOTFS_TEMPLATE = "${S}/rootfs.build.in"

# Recipes whose staged files ride on the disk -> DEPENDS. Add more with one word.
QNX_ROOTFS_INSTALL = "qt-cluster"

# "auto" grows from the floor until it fits; the ~366MB result grew from 192M.
QNX_ROOTFS_SIZE = "auto"
QNX_ROOTFS_MIN = "192M"

do_configure[noexec] = "1"
```

Unlike an image there is **no auto-derived file list** — the guest expects things at
specific paths, so the template states them, mapping a staged tree onto its mount path:

```
[num_sectors=@QNX_ROOTFS_SECTORS@]
[num_inodes=@QNX_ROOTFS_INODES@]
[blksize=@QNX_ROOTFS_BLKSIZE@]

[uid=0 gid=0 perms=0755]

# The whole deploy tree, copied to /qt-cluster. Launch it with /qt-cluster/run.sh.
/qt-cluster=@QNX_ROOTFS_SYSROOT@/qt-cluster

@QNX_ROOTFS_EXTRA@
```

Getting it onto a running guest is three small wirings, all shown worked in
[meta-qnx-guest](../../meta-qnx-guest/README.md): a `virtio-blk` vdev in the guest's
`.qvmconf`, an inline `.rootfs-mount.sh` in its boot script that mounts `/dev/vblk0` at `/`,
and a `QNX_ROOTFS_EXTRA` line in the host data partition's bbappend that places `rootfs.img`
beside the guest IFS.

A host disk's data partition is itself a `qnx-rootfs` recipe whose deployed image
`qnx-disk` wraps into the MBR via `QNX_DISK_DATA_IMG`. Every QNX6 filesystem — whether it
is a guest data disk or a host data partition — goes through this single class.

## Debugging what ended up in an image

**Read the generated build file first.** It is deployed next to the image and is the single
answer to "why is this here":

```bash
less tmp/deploy/images/qnx-aarch64le/my-image.build
```

Then:

```bash
bitbake -c dumpifs my-image             # build if needed, print contents -- no PATH setup
dumpifs my-image.ifs                    # contents (needs $QNX_HOST/usr/bin on PATH)
dumpifs -v my-image.ifs                 # ...with uid/gid/mode
dumpifs -b my-image.ifs                 # basenames only
bitbake -c generate_buildfile my-image  # regenerate without running mkifs
```

### Common errors

| Message | Meaning |
| --- | --- |
| `Host file 'x' not available` | mkifs could not find `x` in any `-r` root or `$QNX_TARGET`. If it is `ls`/`cat`/`uname`, that is toybox — see `QNX_IFS_TOYBOX_CMDS`. Otherwise work out which of the four sources it should come from: [where-things-come-from.md](where-things-come-from.md). |
| `'x' is in QNX_IFS_INSTALL but contributes nothing` | typo, or a recipe that never installed into `${QNX_STAGE_DIR}` |
| `QNX_IFS_ATTR[x] matched no staged file` | key is not a staged basename |
| `... is outside the mkifs search path` | staged somewhere mkifs cannot find by bare name; use `QNX_IFS_EXTRA_ENTRIES` |
| `unparsed line: 'QNX_IFS_ATTR[/bin/x] = ...'` | varflag keys cannot contain `/` — use the basename |
