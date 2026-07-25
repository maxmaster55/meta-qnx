# Showcase

A guided tour of everything the layer does, in one sitting, building up from a single
binary to a flashable disk carrying a hypervisor host and a guest.

This is not the setup guide — see [getting-started.md](getting-started.md) for that, and
come back here. It is also not the reference: each stage links to the
[cookbook](cookbook.md) or [variables.md](variables.md) for the detail.

**Stages 1–9 need only meta-qnx and an SDP.** Stages 10–12 need the project layers
(`meta-qnx-hyp`, `meta-qnx-guest`) and a `QNX_PROJECT_SRC` working tree; they are included
because they are what the mechanism was built for.

| | Stage | Feature |
| --- | --- | --- |
| 1 | [Compile a QNX binary](#1-compile-a-qnx-binary) | `qnx-sdp` |
| 2 | [Put it in a bootable image](#2-put-it-in-a-bootable-image) | `qnx-ifs`, `QNX_IFS_INSTALL` |
| 3 | [Look inside](#3-look-inside) | `-c dumpifs`, the generated `.build` |
| 4 | [Watch dependency tracking work](#4-watch-dependency-tracking-work) | the reason for all this |
| 5 | [Add a second app, and order the boot](#5-add-a-second-app-and-order-the-boot) | `STARTUP_AFTER`, `WAITFOR` |
| 6 | [Reuse an upstream library](#6-reuse-an-upstream-library) | `qnx-autotools`, sysroot handoff |
| 7 | [Build a stock oe-core recipe](#7-build-a-stock-oe-core-recipe) | `qnx-toolchain` |
| 8 | [Fetch a prebuilt OSS package](#8-fetch-a-prebuilt-oss-package) | `-c search_oss`, `qnx-apk` |
| 9 | [Manage the SDP itself](#9-manage-the-sdp-itself) | features, lockfile |
| 10 | [A QNX6 filesystem for big payloads](#10-a-qnx6-filesystem-for-big-payloads) | `qnx-rootfs` |
| 11 | [A flashable disk](#11-a-flashable-disk) | `qnx-disk` |
| 12 | [Host and guest together](#12-host-and-guest-together) | the whole thing |

> **Honest status:** everything below is verified statically — `dumpifs`, `fdisk`, ELF
> checks, boot-header byte comparison against the makefile-built image. **Nothing has been
> run on hardware yet.** Treat stages 11–12 as "builds and inspects correctly", not
> "boots".

---

## 1. Compile a QNX binary

```bash
bitbake qnx-hello
```

The recipe is nine lines and names no image, no path, no `.build` file — it compiles with
`${CC}` and installs into the stage tree. That is the whole contract.

To confirm you got a QNX binary rather than a Linux one, `file` it — the giveaway is the
interpreter:

```
ELF 64-bit LSB executable, ARM aarch64, interpreter /usr/lib/ldqnx-64.so.2
```

You rarely need to check by hand, though: a build system that ignored `${CC}` and used the
host compiler never gets this far. Every staged ELF is verified against the expected
`e_machine` at install time (`QNX_ELF_CHECK`), so a host binary is a build error naming the
file rather than an exec failure on the board.

```bash
bitbake -e qnx-hello | grep '^CC='       # what the recipe will actually run
```

→ [cookbook: a hello-world application](cookbook.md#a-hello-world-application)

## 2. Put it in a bootable image

```bash
bitbake qnx-ifs-hello
```

The image recipe says which recipes it carries:

```bitbake
QNX_IFS_INSTALL = "qnx-hello"
```

**That is the only line that changes when you add an application.** No image file is
edited and no file list is duplicated — the mkifs build file is *generated* from the
recipes installed, each contributing a fragment describing what it ships and what it wants
run at boot.

→ [cookbook: adding it to an image](cookbook.md#adding-it-to-an-image)

## 3. Look inside

```bash
bitbake -c dumpifs qnx-ifs-hello
```

No `PATH` setup, no finding the image by hand. But the more useful artifact is the
**generated build file**, deployed next to the `.ifs`:

```bash
less tmp/deploy/images/qnx-aarch64le/qnx-ifs-hello.build
```

This is the single answer to "why is this in my image". Every entry in it was contributed
by a recipe, and the file records which. When something is present that you did not expect,
or absent that you did, read this before anything else.

→ [cookbook: debugging what ended up in an image](cookbook.md#debugging-what-ended-up-in-an-image)

## 4. Watch dependency tracking work

This is the part that justifies the whole exercise, so it is worth seeing once:

```bash
# edit any .c file in qnx-hello, then rebuild only the IMAGE
bitbake qnx-ifs-hello
```

The application recompiles, restages, and `mkifs` reruns — without anything having told
bitbake that the C file feeds the image. `QNX_IFS_INSTALL` became `DEPENDS`, and the rest
falls out.

In a makefile-driven QNX build, making a rebuilt app reach the image means scraping
`.build` files with `grep`/`sed` to discover which files they stage.

## 5. Add a second app, and order the boot

Adding an application is one word:

```bitbake
QNX_IFS_INSTALL = "qnx-hello qnx-sysinfo"
```

Boot ordering is declared by the *application*, not the image, and needs two knobs that do
different jobs:

```bitbake
QNX_IFS_STARTUP_CMD = "rpi_gpio &"
QNX_IFS_STARTUP_AFTER = "some-driver"      # ordering, like systemd's After=
QNX_IFS_STARTUP_WAITFOR = "/dev/gpio"      # what actually blocks
```

`AFTER` topologically sorts the startup fragments. But a driver started with `&` forks and
returns immediately — long before `resmgr_attach()` has registered its device — so ordering
alone proves nothing. `waitfor`, declared by whoever *provides* the path, is what makes it
real. A dependency cycle is a hard error; a dependency on a recipe not in the image is
silently ignored, so a recipe can safely name optional prerequisites.

An image can suppress a recipe's startup without dropping its files:

```bitbake
QNX_IFS_STARTUP_DISABLE = "qnx-sysinfo"
```

→ [cookbook: a driver or resource manager](cookbook.md#a-driver-or-resource-manager)

## 6. Reuse an upstream library

```bash
bitbake qnx-zlib-user
```

This builds **unmodified upstream zlib** with `qnx-autotools`, then links against it from a
second recipe whose entire connection to it is:

```bitbake
DEPENDS = "zlib"
```

and `-lz`. The stage tree doubles as a compiler sysroot, so "app B needs app A's headers
and library" is a plain `DEPENDS` — the thing a makefile build cannot express without
hand-ordering. Verified: the resulting binary's `NEEDED` list contains `libz.so.1`.

> The classes remove the *toolchain* work, not the *porting* work. A library builds
> unpatched only if its code is portable; something reaching for a Linux `/proc` layout or
> a glibc-only extension still needs the same fixes a hand build would.

→ [cookbook: a library reused from upstream](cookbook.md#a-library-reused-from-upstream-autotools)

## 7. Build a stock oe-core recipe

```bash
bitbake qnx-ifs-reuse
```

An IFS whose **entire payload is unmodified oe-core** — poky's own `bzip2` (autotools) and
`json-c` (cmake), neither written with QNX in mind, shared libraries included. With
`qnx-toolchain` enabled, `qcc` becomes the default toolchain for every target recipe, so a
stock recipe builds for QNX and installs into an image by name.

The honest limit: buildability is per-*recipe*, not per-*layer*. It works for portable
C/C++ libraries; code or dependency closures that assume Linux/glibc still need porting.

→ [reusing-layers.md](reusing-layers.md)

## 8. Fetch a prebuilt OSS package

You do not need to know the package name in advance:

```bash
echo 'QNX_OSS_SEARCH = "sqlite"' > oss-search.conf
bitbake -c search_oss qnx-sdp -R oss-search.conf
```

This reads each channel's `APKINDEX` and prints name, version, size, channel and
description. When the result narrows to four or fewer it prints a **paste-ready recipe**,
because the index carries the summary, homepage, licence and dependencies a recipe needs:

```bitbake
--- dbus_1.16.2-r2.bb ------------------------
SUMMARY = "Freedesktop.org message bus system"
HOMEPAGE = "https://www.freedesktop.org/Software/dbus"
LICENSE = "AFL-2.1 OR GPL-2.0-or-later"

inherit qnx-apk

QNX_OSS_CHANNEL = "8.0.3/extra"

# Run 'bitbake -c fetch dbus' once and paste the checksum it prints.
SRC_URI[sha256sum] = ""

# Depends on: glib qnx-io-sock
```

The sha256 is the one thing the index cannot supply — it records a SHA1 — so the stub
points at the standard "fetch once and paste" loop.

→ [where-things-come-from.md](where-things-come-from.md) · [sdp.md](sdp.md#bitbake--c-search_oss-qnx-sdp)

## 9. Manage the SDP itself

The SDP is not built by Yocto, but what is *in* it can be declared, checked and installed:

```bash
bitbake -c check_sdp qnx-sdp        # does the install match this project? (offline, <1s)
bitbake -c search qnx-sdp           # what does the catalogue offer?
bitbake -c resolve_sdp qnx-sdp      # what would my features install, and is it satisfiable?
bitbake -c install_sdp qnx-sdp      # do it (network + credentials)
bitbake -c write_lockfile qnx-sdp   # record the result
```

The split follows `package.json` / `package-lock.json`: `QNX_SDP_FEATURES` is readable
intent, the lockfile is the resolved snapshot. **You never hand-write a version.** Image
builds depend on `check_sdp` by default, so a missing package is a named error instead of
`Host file 'x' not available` with a build-file line number.

Features are namespace **glob patterns**, not enumerations, which is why a subsystem is two
patterns rather than forty package ids:

```bitbake
QNX_SDP_FEATURE[networking] = "target.net.*"
QNX_SDP_FEATURES += "networking"
```

→ [sdp.md](sdp.md)

## 10. A QNX6 filesystem for big payloads

An IFS is copied into RAM whole at boot, so a large runtime — Qt, a graphics stack —
cannot live in one. `qnx-rootfs` builds a bare QNX6 filesystem image instead, and carries
recipes exactly the way an image does:

```bitbake
inherit qnx-rootfs
QNX_ROOTFS_INSTALL = "qt-cluster"
QNX_ROOTFS_SIZE = "auto"
QNX_ROOTFS_MIN = "192M"
```

`auto` starts at the floor and grows until `mkqnx6fsimg` stops complaining, because real
filesystem overhead is not predictable from a byte count. An explicit size never grows — if
you asked for 512M you want to be told it does not fit, not to silently get more.

This is the **single class for every QNX6 filesystem**: a guest's data disk and a host
disk's data partition are the same thing built the same way.

```bash
bitbake qnx-guest-rootfs
```

→ [cookbook: a data disk for payloads too big for an IFS](cookbook.md#a-data-disk-for-payloads-too-big-for-an-ifs)

## 11. A flashable disk

```bash
bitbake qnx-host-disk
```

`qnx-disk` builds the FAT boot partition with `mkfatfsimg`, wraps it and a pre-built data
partition into an MBR with `diskimage`, and sizes everything from what actually went in —
where a QNX BSP carries hand-maintained `***CYLINDERS MODIFIED BY BUILD` markers for a
script to patch.

The data partition is a `qnx-rootfs` recipe's deployed image, named by `QNX_DISK_DATA_IMG`.

```bash
cd tmp/deploy/images/qnx-aarch64le
fdisk -l qnx-host-disk.img        # bootable FAT32 + type-179 QNX6
sudo bmaptool copy qnx-host-disk.img /dev/sdX
```

The intermediate `part-*.img`, `boot.build` and `disk.cfg` are deployed alongside — those
are what you read when a disk does not boot.

→ [cookbook: a flashable SD card image](cookbook.md#a-flashable-sd-card-image)

## 12. Host and guest together

The payoff, and the thing the layer was written against: a Raspberry Pi 5 hypervisor host
image plus a QNX guest, from two project layers that meta-qnx knows nothing about.

```bash
bitbake qnx-host-disk      # with meta-qnx-guest in the build, the guest lands on it
```

Three mechanisms carry the whole arrangement, and none required changing meta-qnx:

- **Boot configuration lives on the image, not the machine.** Host and guest are both
  aarch64le QNX but differ in load address, image format and startup program. One tree
  legitimately produces both — the host overrides `QNX_IMAGE_ADDR`, `QNX_IMAGE_VIRTUAL`
  and `QNX_STARTUP`; the guest sets none of them, because the defaults already describe a
  guest.
- **Shared `#include` fragments.** Host and guest images share their boot header, startup
  preamble and base utilities instead of being two copies of one file.
- **A bbappend keeps the layer arrow pointing one way.** meta-qnx-guest appends the host's
  data partition recipe to drop its IFS, `.qvmconf` and `rootfs.img` into
  `/guests/guest-1/`. The host layer never reaches for a guest, so a build without
  meta-qnx-guest produces a data partition with no guests rather than failing.

The generated host image's boot header is byte-identical to the makefile-built
`ifs-rpi5-hyp.bin` — same load address, startup size, entry point and flags.

→ [sharing-between-images.md](sharing-between-images.md)

---

## Feature index

Everything above, mapped to where it is specified.

| Feature | Class / task | Reference |
| --- | --- | --- |
| Compile with `qcc` | `qnx-sdp` | [variables: staging paths](variables.md#staging-paths) |
| CMake / meson / autotools | `qnx-cmake`, `qnx-meson`, `qnx-autotools` | [cookbook](cookbook.md) |
| Fetch from git, or build a tree in place | `qnx-src` | [variables: application sources](variables.md#application-sources) |
| Stock oe-core recipes for QNX | `qnx-toolchain` | [reusing-layers.md](reusing-layers.md) |
| Prebuilt `.apk` packages | `qnx-apk`, `-c search_oss` | [where-things-come-from.md](where-things-come-from.md) |
| Bootable IFS | `qnx-ifs` | [variables: image recipes](variables.md#image-recipes) |
| What a recipe puts in an image | `qnx-image-contract` | [variables: application recipes](variables.md#application-recipes) |
| Named sets of recipes | `qnx-packagegroup` | [sharing-between-images.md](sharing-between-images.md) |
| QNX6 filesystem images | `qnx-rootfs` | [variables: rootfs](variables.md#qnx6-filesystem-images-rootfs) |
| Flashable MBR disks | `qnx-disk` | [variables: disk images](variables.md#disk-images) |
| SDP contents | `qnx-sdp-packages` | [sdp.md](sdp.md) |
| Where anything comes from | — | [where-things-come-from.md](where-things-come-from.md) |
