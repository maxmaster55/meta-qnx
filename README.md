# meta-qnx

A Yocto layer that builds **QNX** artifacts — QNX binaries with `qcc`, and bootable
QNX image filesystems (IFS) with `mkifs` — using bitbake as the build orchestrator.

Status: **proof of concept.** It builds a hello-world binary and a minimal bootable
aarch64le guest IFS containing it.

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

The payoff over hand-written makefiles is dependency tracking. In a makefile-driven QNX
build, making a rebuilt app actually reach the image means scraping the `.build` file with
`grep`/`sed` to discover which files it stages. Here it is one line:

```
DEPENDS = "qnx-hello"
```

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

```
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
| `classes/qnx-ifs.bbclass` | Runs `mkifs` and deploys the resulting `.ifs` (+ `.sym` files). |
| `conf/machine/qnx-aarch64le.conf` | Thin machine: no kernel, no bootloader, no rootfs. |
| `recipes-example/qnx-hello/` | Hello-world C program built with `qcc`. |
| `recipes-image/qnx-ifs-hello/` | Minimal bootable IFS containing it. |

### The staging contract

Recipes install target files under `${D}${QNX_STAGE_DIR}`, laid out to mirror
`$QNX_TARGET`:

```
${QNX_STAGE_DIR}/aarch64le/{bin,sbin,lib}/...
```

That layout is not arbitrary — it is what `mkifs -r <root>` expects, and it matches the
hand-built `install/` trees in an existing QNX BSP (`install/aarch64le/sbin/...`). Keeping
the convention means existing `.build` files remain reusable verbatim. `SYSROOT_DIRS` makes
the tree flow into a dependent recipe's `RECIPE_SYSROOT` through a plain `DEPENDS`.

## Not done yet

1. A `qnx-sdp-native` recipe wrapping `qnxsoftwarecenter_clt -importAndInstall`, so the SDP
   itself is provisioned by bitbake instead of by hand.
2. Recipes for real applications. Most QNX app trees already have makefiles or CMake, so a
   `qnx-sdp`-inheriting recipe with `oe_runmake` is largely mechanical.
3. `mkqnx6fsimg` / `mkfatfsimg` / `diskimage` support, to produce a full bootable
   `disk.img` (FAT boot partition + QNX6 data partition) rather than just an IFS.
