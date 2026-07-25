# meta-qnx

A Yocto layer that builds **QNX** artifacts — QNX binaries with `qcc`, and bootable QNX
image filesystems (IFS) with `mkifs` — using bitbake as the build orchestrator.

**Documentation:**
[Getting started](docs/getting-started.md) ·
[Showcase](docs/showcase.md) — a tour of every feature ·
[Where things come from](docs/where-things-come-from.md) ·
[Variable reference](docs/variables.md) ·
[Cookbook](docs/cookbook.md) ·
[Reusing normal Yocto layers](docs/reusing-layers.md) ·
[Sharing between images](docs/sharing-between-images.md) ·
[Managing the SDP](docs/sdp.md)

Status: **working proof of concept.**

This layer is **mechanism only** — no board, project or application policy. Everything it
ships is a class, the generic aarch64le machine, or a self-contained example. A project
layer supplies the rest; `meta-qnx-hyp` is a worked example that builds a Raspberry Pi 5
hypervisor host image without meta-qnx knowing anything about the Pi.

## Can Yocto really build QNX?

Not the way it builds Linux, no. Be clear about this before investing in it:

- There is no QNX `TCLIBC`, no `TARGET_OS=nto`, no `procnto` recipe, no `.ipk`/`.rpm`
  packaging of QNX binaries, and no `do_rootfs`.
- Everything QNX — the kernel, libc, drivers, shells, utilities — arrives as prebuilt
  binaries in a QNX SDP installed by `qnxsoftwarecenter_clt`. Yocto does not and cannot
  compile them.

What *does* work, and what this layer does, is use bitbake purely as a **task engine and
dependency graph** on top of an existing SDP. Recipes shell out to `qcc`/`q++`/`mkifs`
while Yocto's own cross-toolchain, packaging and rootfs machinery are switched off.

Known cosmetic wart: `TARGET_OS` stays `linux` in bitbake's metadata. Nothing here invokes
Yocto's cross-gcc, sysroot or packaging, so the triplet is never used. Making bitbake
believe in `aarch64-unknown-nto-qnx8.0.0` would mean patching `siteinfo.bbclass` and
inventing a TCLIBC, for no practical gain.

## What it gives you over makefiles

**Adding an application is one word**, exactly like `IMAGE_INSTALL` on Linux:

```bitbake
QNX_IFS_INSTALL = "qnx-hello rpi-gpio"
```

No image file is edited, and no list of files is duplicated. The mkifs build file is
*generated* from the recipes installed; each recipe contributes a fragment describing what
it ships and what it wants run at boot. The generated file is deployed next to the `.ifs`,
so there is always one place that explains what went in.

**Dependency tracking falls out for free.** In a makefile-driven QNX build, making a
rebuilt app reach the image means scraping `.build` files with `grep`/`sed` to discover
which files they stage. Here `QNX_IFS_INSTALL` becomes `DEPENDS`, and bitbake reruns
`mkifs` when any installed recipe changes.

**Libraries work between recipes.** The stage tree doubles as a compiler sysroot, so
"app B needs app A's headers and library" is a plain `DEPENDS` — the thing a makefile build
cannot express without hand-ordering.

**You can reuse recipes from normal Yocto layers.** With `qnx-toolchain` enabled (see
[docs/reusing-layers.md](docs/reusing-layers.md)), `qcc` becomes the default toolchain for
every target recipe, so a **stock** recipe — poky's own `bzip2`, a library from
`meta-openembedded` — builds for QNX unmodified, and installs into an image by name.
Proven end to end on upstream zlib, and on stock oe-core bzip2 (autotools) and json-c
(cmake), shared libraries included. The honest limit: buildability is per-*recipe*, not
per-*layer* — it works for portable C/C++ libraries; code or dependency closures that
assume Linux/glibc still need porting.

## Quick start

```bash
# One command creates a configured build directory (assumes meta-qnx beside poky):
TEMPLATECONF=meta-qnx/conf/templates/default source poky/oe-init-build-env build-qnx
# then point QNX_SDP_ROOT in conf/local.conf at your SDP. It defaults to
# ${TOPDIR}/qnx-sdp, like DL_DIR, so that is the only line you normally change.

bitbake qnx-ifs-hello                                  # a bootable IFS
bitbake qnx-host-disk                                  # ...on a flashable disk image
bitbake -c dumpifs qnx-ifs-hello                       # print what went into it
```

(In an existing build directory, add meta-qnx to `conf/bblayers.conf` and paste
`conf/local.conf.sample` into `conf/local.conf` instead.)

No SDP yet? Leave `QNX_SDP_ROOT` alone and run `bitbake -c install_sdp qnx-sdp` to create
one in the build directory — see [docs/sdp.md](docs/sdp.md).

Full instructions in [docs/getting-started.md](docs/getting-started.md).

## Layout

| Path | Purpose |
| --- | --- |
| `classes/qnx-sdp.bbclass` | Points `CC`/`CXX`/… at `qcc`/`q++`, exports the SDP env, disables Yocto's toolchain and packaging, defines the staging contract. Inherited by our own recipes. |
| `classes/qnx-toolchain.bbclass` | Makes `qcc` the default toolchain for **every** target recipe (via global `INHERIT`), so a stock recipe from a normal layer builds for QNX with no wrapper. Corrects oe-core's CMake toolchain file, which would otherwise say Linux/x86-64. Guarded, opt-in. |
| `classes/qnx-image-contract.bbclass` | How **any** recipe declares what it puts in an image: the `ifs.d` drop-in format, startup ordering, per-entry `mkifs` attributes. Shared by `qnx-sdp` recipes and stock ones, which is why it is not part of either. |
| `classes/qnx-packagegroup.bbclass` | A named, reusable set of recipes — one word in an image instead of a list two images have to keep in step. |
| `classes/qnx-ifs.bbclass` | Expands `QNX_IFS_INSTALL` into a generated `.build` file, runs `mkifs`, deploys the results. |
| `classes/qnx-cmake.bbclass` | CMake projects: generates a QNX toolchain file, drives configure/build/install. |
| `classes/qnx-meson.bbclass` | Meson projects: generates a cross file, synthesises `.pc` files for SDP libraries. |
| `classes/qnx-autotools.bbclass` | `./configure` + `make` projects: drives configure with qcc and the stage-tree install dirs. Reuses portable upstream libraries (zlib verified) with no patches. |
| `classes/qnx-src.bbclass` | Application sources: fetch from a git repository, or build a local working tree in place via `externalsrc`. |
| `classes/qnx-disk.bbclass` | FAT boot partition + optional pre-built data partition wrapped in an MBR: a flashable `.img`, sized automatically. |
| `classes/qnx-rootfs.bbclass` | The single class for every QNX6 filesystem image (`mkqnx6fsimg`) — guest data disks, host data partitions, anything that is a bare QNX6 filesystem. A disk recipe wraps one via `QNX_DISK_DATA_IMG`. |
| `classes/qnx-sdp-packages.bbclass` | Feature-to-package resolution and lockfile handling for the SDP. |
| `classes/qnx-apk.bbclass` | Fetch, extract and stage a prebuilt package from QNX's OSS repository. |
| `recipes-sdp/qnx-sdp/` | Tasks to check, search, resolve and install SDP packages. |
| `conf/machine/qnx-aarch64le.conf` | Thin machine: no kernel, no bootloader, no rootfs. |
| `conf/qnx-sdp-features.inc` | Feature definitions: names mapped to package id patterns. |
| `conf/templates/default/` | `TEMPLATECONF` build templates: one command creates a configured build directory. |
| `conf/local.conf.sample` | Copy-paste configuration block for an existing build directory. |
| `recipes-example/qnx-hello/` | Hello-world C program built with `qcc`. |
| `recipes-example/qnx-sysinfo/` | Second app, showing that adding one costs one word. |
| `recipes-image/qnx-ifs-hello/` | Minimal bootable IFS, plus the `.build.in` template. |
| `recipes-image/qnx-ifs-reuse/` | An IFS whose **entire payload is unmodified oe-core** — proof that a recipe nobody here wrote can be built for QNX and installed by name. One recipe per build system: bzip2 (autotools), json-c (cmake). |
| `files/ifs/*.build.inc` | Shared `.build` fragments (boot header, startup preamble, base utilities, block and network stacks) that host and guest images both `#include`. |
| `recipes-example/zlib/` | Unmodified upstream zlib via `qnx-autotools` — a reused OSS library, no patches. |
| `recipes-example/qnx-zlib-user/` | Links `-lz` against that zlib through a plain `DEPENDS` — proves the sysroot handoff. |

## Design notes

Things that are the way they are for a reason, and will look wrong otherwise.

**The stage tree is also the sysroot.** `$QNX_TARGET`'s layout suits both roles —
`mkifs -r` wants `${PROCESSOR}/{bin,sbin,lib}`, a compiler wants `usr/include` and
`${PROCESSOR}/lib` — so one tree serves both, and existing QNX `install/` trees already
work this way. Headers and `.a` files are routed to the sysroot only, never into an image.

**Boot configuration lives on the image, not the machine.** A hypervisor host and its
guests are both aarch64le QNX but differ in load address, image format and startup program.
One tree legitimately produces both, exactly as `qnx_host/` and `qnx_guests/` do.

**Templates use `@VAR@`, not `${VAR}`.** mkifs build files use `${...}` for their own
variables (`${PROCESSOR}`, `${QNX_TARGET}`); expanding those would corrupt the file.

**mkifs attributes are passed through, not modelled.** mkifs has ~34 record attributes;
`QNX_IFS_ATTR[name] = "uid=0 perms=4755"` reaches all of them, including future additions.

**Boot ordering needs two knobs.** `QNX_IFS_STARTUP_AFTER` declares dependencies between
commands (like systemd's `After=`), but a driver started with `&` returns before its device
exists — `QNX_IFS_STARTUP_WAITFOR` is what actually blocks.

**toybox provides `ls`.** QNX 8 ships no standalone `ls`, `cat`, `cp` or `uname`; they are
all one multicall binary. Images get it plus a link per command automatically.

**Reusing upstream libraries costs a class, not a fork.** `qnx-cmake`, `qnx-meson` and
`qnx-autotools` are the three build-system drivers. A portable upstream library builds for
QNX with `inherit qnx-autotools` (or `-cmake`/`-meson`) plus its tarball URL and no code
patches — verified against unmodified upstream zlib, which stages `libz` + `zlib.h` that
another recipe then links with a one-line `DEPENDS`. The compiler is portable; only the
*build-system metadata* of a stock OE recipe (its `ptest`/native/packaging assumptions) is
Linux-bound, which is why the driver classes reuse the recipe *body* rather than trying to
consume a foreign `.bb` wholesale. Consuming stock meta-oe recipes unmodified would instead
need a full QNX `TCLIBC` provider — a much larger, release-tracking commitment.

**`POPULATESYSROOTDEPS` is cleared.** `staging.bbclass` makes every target recipe's
`do_populate_sysroot` depend on target binutils purely so it can strip. That one dependency
drags in `binutils-cross` and Yocto's entire cross toolchain — ~190 tasks and a large
download, none of it ever used.

## Not done yet

1. The SDP version is not in the task hash, only its path — upgrading the SDP in place will
   not trigger rebuilds.
2. A check that every bare name in a generated build file resolves against the search
   roots, which would catch the `Host file 'x' not available` class of error before mkifs
   runs. (The other half of this — verifying staged binaries really are QNX target ELFs,
   catching a build system that ignored `${CC}` — is done: see `QNX_ELF_CHECK`.)
