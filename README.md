# meta-qnx

A Yocto layer that builds **QNX** artifacts — QNX binaries with `qcc`, and bootable
QNX image filesystems (IFS) with `mkifs` — using bitbake as the build orchestrator.

Status: **working proof of concept.**

This layer is **mechanism only** — it contains no board, no project and no application
policy. Everything it ships is either a class, the generic aarch64le machine, or a
self-contained example. A project layer supplies the rest; `meta-qnx-hyp` is a worked
example that builds a Raspberry Pi 5 hypervisor host image without meta-qnx knowing
anything about the Pi.

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

## Adding an application

Exactly like `IMAGE_INSTALL` on Linux — one word in the image recipe:

```bitbake
QNX_IFS_INSTALL = "qnx-hello qnx-sysinfo"
```

That is the whole change. **No image file is edited to gain an application**, and no list
of files is duplicated anywhere. An application recipe declares nothing about the image:

```bitbake
inherit qnx-sdp
QNX_IFS_STARTUP_CMD = "qnx-sysinfo"     # optional: run it at boot

do_install() {
    install -d ${D}${QNX_STAGE_BINDIR}
    install -m 0755 qnx-sysinfo ${D}${QNX_STAGE_BINDIR}/qnx-sysinfo
}
```

Note what is absent: no path inside the image, no list of files, no mention of a `.build`
file. The `/bin/qnx-sysinfo` entry is derived from what `do_install` staged.

### How it works

The `.build` file is **generated**, not maintained. Each recipe drops a fragment of mkifs
syntax into the stage tree describing what it contributes:

| Drop-in | Contents |
| --- | --- |
| `${QNX_IFS_DROPIN_DIR}/${PN}.files` | mkifs entries, one per staged file (automatic) |
| `${QNX_IFS_DROPIN_DIR}/${PN}.startup` | startup-script lines, from `QNX_IFS_STARTUP_CMD` |

The image recipe concatenates the fragments of everything in `QNX_IFS_INSTALL` into a
template's `@QNX_IFS_FILES@` and `@QNX_IFS_STARTUP@` markers. Same idea as an
`/etc/something.d` directory: the app owns its entry, and the image never enumerates its
members. The generated file is deployed next to the `.ifs`, so when something is in the
image and you cannot see why, there is one file that explains it.

The template keeps only what is genuinely image-specific: the boot line, the console
driver, the startup-script skeleton. You touch it when the *image* changes, not when an
*application* does.

### Boot ordering

A resource manager usually needs a driver up first. Two knobs, and you need
both — priority alone is a trap:

```bitbake
QNX_IFS_STARTUP_CMD = "rpi_gpio &"
QNX_IFS_STARTUP_PRIORITY = "300"      # lower runs earlier; default 500
QNX_IFS_STARTUP_WAITFOR = "/dev/gpio" # block until it actually exists
```

Priority only orders the *commands*. A driver started with `&` forks and returns
immediately, so the next command can still run before the device node exists —
a classic QNX boot race. `QNX_IFS_STARTUP_WAITFOR` emits `waitfor <path> <timeout>`
after the command, which is what genuinely blocks; it is the same idiom the project's
own build files use (`devb-virtio ...` followed by `waitfor /dev/hd0`).

It is declared by whoever *provides* the path, so everything later in the sequence is
safe without needing to know who to wait for.

Conventional bands, so unrelated recipes order correctly without knowing about each
other:

| Priority | For |
| --- | --- |
| 100 | hardware drivers, anything providing a `/dev` entry |
| 300 | resource managers and services built on those |
| 500 | applications (default) |
| 700 | anything wanting the system fully up |

Equal priorities fall back to `QNX_IFS_INSTALL` order, so listing order stays a usable
tiebreak. The generated result is plain to read:

```text
### rpi-gpio prio=300
rpi_gpio &
waitfor /dev/gpio 5
### qnx-hello prio=500
qnx-hello
### qnx-sysinfo prio=700
qnx-sysinfo
```

### toybox

QNX 8 ships **no standalone `ls`, `cat`, `cp`, `uname` or `grep`** — there is nothing at
`$QNX_TARGET/${PROCESSOR}/bin` called any of those. They all come from `toybox`, a single
multicall binary that dispatches on `argv[0]`. A build file naming `ls` therefore fails
with the unhelpful `Host file 'ls' not available` and a line number.

Images get it automatically: the binary once, plus a `[type=link]` per command, as the
SDP's own toybox documentation prescribes. 62 commands cost one ~380 KB binary.

```bitbake
QNX_IFS_TOYBOX_CMDS = ""            # opt out entirely
QNX_IFS_TOYBOX_CMDS += "vi bc"      # or extend the default set
```

Note the links use an absolute target (`/bin/ls -> /usr/bin/toybox`). The SDP docs show a
bare `=toybox`, but a symlink target without a leading slash resolves relative to the
link's own directory, so `/bin/ls` would look for a non-existent `/bin/toybox`.

### mkifs attributes

mkifs takes attributes in brackets before a record — `[uid=0 gid=0 perms=4755]` and about
thirty others (`type`, `prefix`, `search`, `data`, `filter`, `cksum`, `sha256`, `chain`,
`module`, `mtime`, `dperms`, `keepsection`, …). Rather than model each one, the value is
**passed through verbatim**, so every record attribute is reachable — including any a
future SDP adds:

```bitbake
QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"
QNX_IFS_DEFAULT_ATTR = "uid=0 gid=0"          # applied to all of this recipe's entries
QNX_IFS_DEST[myapp] = "/proc/boot/myapp"      # override the derived destination
```

Keys are **basenames, not paths**: bitbake varflag names may only contain
`[a-zA-Z0-9-_+.@]`, so `QNX_IFS_ATTR[/sbin/rpi_gpio]` is a parse error rather than a lookup
that quietly fails. A key matching no staged file warns.

Attributes describing the *image* rather than a record (`image`, `virtual`, `ram`,
`pagesize`, `cpu`, `physical`, `vboot`) belong to the boot environment — set them as
template `@VARIABLE@`s, see [Describing an image](#describing-an-image).

Escape hatches, for entries with no staged file behind them:

- `QNX_IFS_EXTRA_ENTRIES` — raw mkifs lines for symlinks into `/tmp` or `/dev`, inline
  config bodies, `[search=...]`. Multiple entries are separated by a literal `\n`:
  bitbake does not process escape sequences in variable values, so there is otherwise no
  way to write a multi-line value (a line continuation collapses to a space).
- `QNX_IFS_AUTO_ENTRIES = "0"` — spell out every entry by hand

Beyond that, dependency tracking falls out for free. In a makefile-driven QNX build,
making a rebuilt app reach the image means scraping the `.build` file with `grep`/`sed` to
discover which files it stages. Here `QNX_IFS_INSTALL` becomes `DEPENDS`, and bitbake
reruns `mkifs` when any installed recipe changes.

Known cosmetic wart: `TARGET_OS` stays `linux` in bitbake's metadata. Nothing here invokes
Yocto's cross-gcc, sysroot or packaging, so the triplet is never used. Making bitbake
believe in `aarch64-unknown-nto-qnx8.0.0` would mean patching `siteinfo.bbclass` and
inventing a TCLIBC, for no practical gain.

## Requirements

- Poky **scarthgap** (5.0.x). `LAYERSERIES_COMPAT` is set accordingly.
- An installed QNX SDP 8.0 with a valid licence in `$HOME/.qnx`.
  The SDP is used **strictly read-only**; nothing here writes to, cleans, or
  reinstalls it.

## Usage

```bash
source poky/oe-init-build-env build-qnx
```

In `conf/local.conf`:

```bitbake
MACHINE = "qnx-aarch64le"
QNX_SDP_ROOT = "/path/to/qnx800"
```

Add this layer to `conf/bblayers.conf`, then:

```bash
bitbake qnx-hello        # compiles a QNX aarch64 binary with qcc
bitbake qnx-ifs-hello    # assembles it into a bootable IFS with mkifs
```

Artifacts land in `tmp/deploy/images/qnx-aarch64le/`.

Verify without hardware:

```bash
file tmp/deploy/images/qnx-aarch64le/qnx-hello.ifs
dumpifs tmp/deploy/images/qnx-aarch64le/qnx-hello.ifs | grep qnx-hello
```

The IFS is a drop-in for a QNX hypervisor guest: it expects a `virtio-console` vdev at
`loc 0x20000000` / `intr gic:42`, matching the stock guest `.qvmconf` in the QNX BSP.

## Layout

| Path | Purpose |
| --- | --- |
| `classes/qnx-sdp.bbclass` | Points `CC`/`CXX`/… at `qcc`/`q++`, exports the SDP env, disables Yocto's toolchain and packaging, defines the staging contract. |
| `classes/qnx-ifs.bbclass` | Expands `QNX_IFS_INSTALL` into a generated `.build` file, runs `mkifs`, deploys the `.ifs` (+ `.sym` files). |
| `classes/qnx-cmake.bbclass` | CMake projects: generates a QNX toolchain file, drives configure/build/install. |
| `classes/qnx-project-src.bbclass` | Builds an application working tree in place via `externalsrc`. |
| `conf/machine/qnx-aarch64le.conf` | Thin machine: no kernel, no bootloader, no rootfs. |
| `recipes-example/qnx-hello/` | Hello-world C program built with `qcc`. |
| `recipes-example/qnx-sysinfo/` | Second app, existing to show that adding one costs one word. |
| `recipes-image/qnx-ifs-hello/` | Minimal bootable IFS, plus the `.build.in` template. |

### The staging contract

Recipes install target files under `${D}${QNX_STAGE_DIR}`, laid out to mirror
`$QNX_TARGET`:

```text
${QNX_STAGE_DIR}/aarch64le/{bin,sbin,lib}/...   # runtime: image + link
${QNX_STAGE_DIR}/usr/include/...                # headers: sysroot only
```

That layout is not arbitrary — it is what `mkifs -r <root>` expects, and it matches the
hand-built `install/` trees in an existing QNX BSP (`install/aarch64le/sbin/...`). Keeping
the convention means existing `.build` files remain reusable verbatim. `SYSROOT_DIRS` makes
the tree flow into a dependent recipe's `RECIPE_SYSROOT` through a plain `DEPENDS`.

**One tree serves two roles.** The same layout that `mkifs -r` wants is also what a
compiler wants, so the stage tree doubles as the sysroot: `qnx-sdp.bbclass` adds
`-I<sysroot>/usr/include` and `-L<sysroot>/aarch64le/lib` to every recipe's flags. That is
what turns "app B needs app A's library and headers" into a plain `DEPENDS` — the thing a
makefile build cannot express, and the reason `src/Makefile` has to hand-order `someip`
before `motor_ai_*`.

Routing between the two roles is automatic:

| Staged path | Goes to |
| --- | --- |
| `aarch64le/{bin,sbin,lib,usr/*}` | image **and** sysroot |
| `usr/include/...`, `*.a`, `*.pc` | sysroot only — never wastes IFS RAM |
| symlinks | emitted as `[type=link]`, so a versioned `.so` chain is not duplicated |

Anything staged outside the mkifs search path warns rather than vanishing quietly.

## Building applications

| Class | For |
| --- | --- |
| `qnx-sdp` | plain recipes; `oe_runmake` and hand-written compile steps |
| `qnx-cmake` | CMake projects; generates a QNX toolchain file whose `CMAKE_FIND_ROOT_PATH` covers both the SDP and the recipe sysroot |
| `qnx-project-src` | builds a working tree in place via `externalsrc` |

`qnx-cmake` is deliberately **not** built on OE's `cmake.bbclass`, which assumes Yocto's
cross-toolchain, sysroot layout and a native cmake recipe — all of which `qnx-sdp`
switches off. Driving cmake directly is less work than unpicking those assumptions. It
uses the host's `cmake`/`ninja` (added to `HOSTTOOLS` in `conf/layer.conf`).

`qnx-project-src` exists because the applications live in a separate, actively edited
repository, several as branch-tracking submodules. A recipe with a pinned `SRCREV` would
mean committing to see a change — exactly the friction that sends people back to running
`make` by hand. Point it at a checkout:

```bitbake
QNX_PROJECT_SRC = "/path/to/Qnx_Hypervisor_rbye"
```

Trade-off: `externalsrc` disables sstate for those recipes, so `do_compile` runs every
time. That is the right default while porting; a recipe that has stabilised can move to a
real `SRC_URI` with a pinned revision.

Worked examples of both live in `meta-qnx-hyp`: `shm-chunker` (plain make) and `rpi-gpio`
(CMake, and notably a recipe with *no install code at all* — the project's own `install()`
rules already target the right layout).

## Describing an image

An image recipe sets its boot environment; the template refers to it through `@VARIABLE@`
markers, which are expanded from the datastore. That is what lets one layer describe both
a hypervisor host and its guests:

| Variable | Default (guest) | Host example |
| --- | --- | --- |
| `QNX_IMAGE_ADDR` | `0x80000000` | `0x80000` |
| `QNX_IMAGE_VIRTUAL` | `${QNX_PROCESSOR},elf` | `${QNX_PROCESSOR},raw -compress` |
| `QNX_STARTUP` | `startup-armv8_fm` | `startup-bcm2712-rpi5` |
| `QNX_STARTUP_ARGS` | `-H` | `-v -u reg -a -W 5000 -Q enable,el1-host` |
| `QNX_KERNEL` | `procnto-smp-instr` | — |

These are image properties, not machine properties: one aarch64le tree legitimately
produces both, exactly as the project's `qnx_host/` and `qnx_guests/` do.

bitbake's own `${...}` syntax is deliberately *not* used for this — mkifs build files use
`${...}` for their own variables (`${PROCESSOR}`, `${QNX_TARGET}`), and expanding those
here would corrupt them.

### Extra search roots

`QNX_IFS_EXTRA_ROOTS` adds further `mkifs -r` roots, searched after the recipe sysroot and
before `$QNX_TARGET`. A board layer needs this when the SDP does not ship its drivers — an
RPi5 host image needs `startup-bcm2712-rpi5`, `i2c-dwc-rpi5` and `gpio-rp1`, none of which
exist under `$QNX_TARGET`.

## Not done yet

1. A `qnx-sdp-native` recipe wrapping `qnxsoftwarecenter_clt -importAndInstall`, so the SDP
   itself is provisioned by bitbake instead of by hand.
2. A meson class, for the GPU dependencies (`libepoxy`, `virglrenderer`) — `src/qnx-aarch64le.ini`
   is already a meson cross file and can be templated the way `qnx-cmake` templates its toolchain file.
3. Routing image content to a QNX6 data partition (`mkqnx6fsimg`) rather than the IFS.
   An IFS is RAM-resident, which is why `guest-1` already carries a separate `rootfs.img`.
4. The SDP version is not in the task hash, only its path -- upgrading the SDP in place will
   not trigger rebuilds.
5. A QA check that staged binaries really are QNX aarch64 ELFs, to catch a recipe whose
   build system ignored `${CC}` and used the host compiler.
6. `mkfatfsimg` / `diskimage` support, to produce a full bootable `disk.img`
   (FAT boot partition + QNX6 data partition) rather than just an IFS.
