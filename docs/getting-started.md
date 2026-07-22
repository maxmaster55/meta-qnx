# Getting started

## What you need

- **Poky scarthgap (5.0.x).** `LAYERSERIES_COMPAT` is set to `scarthgap`; other releases
  will refuse to parse the layer.
- **A QNX SDP 8.0 install**, with a valid licence in `$HOME/.qnx`. The SDP is used
  **strictly read-only** — nothing in this layer writes to, cleans or reinstalls it.
- **`cmake` and `ninja` on the host**, if you use `qnx-cmake`. The layer adds them to
  `HOSTTOOLS` rather than building native recipes for them.

You do **not** need to source `qnxsdp-env.sh`. `qcc` runs from a plain environment given
only `QNX_HOST`, `QNX_TARGET` and `PATH`, which is what makes this layer possible; the
classes set those themselves.

## Set up a build

```bash
cd /path/to/yocto
source poky/oe-init-build-env build-qnx
```

Add the layer to `conf/bblayers.conf`:

```bitbake
BBLAYERS ?= " \
  /path/to/poky/meta \
  /path/to/poky/meta-poky \
  /path/to/meta-qnx \
  "
```

Nothing here needs `meta-openembedded`, `meta-raspberrypi` or any BSP layer.

Then in `conf/local.conf`:

```bitbake
MACHINE = "qnx-aarch64le"
QNX_SDP_ROOT = "/path/to/qnx800"

# Optional: only needed for recipes that build a working tree in place.
QNX_PROJECT_SRC = "/path/to/your/qnx-project"
```

### Two settings worth turning off

```bitbake
# Downloads a ~50MB glibc shim before anything can run, to make Yocto's own native
# binaries portable across host distros. This layer builds no native binaries, so it is
# pure network dependency for zero benefit -- and it is what a build hangs on when the
# network is down.
INHERIT:remove = "uninative"

# Nothing here has a CVE database to check or an SBOM worth generating.
INHERIT:remove = "create-spdx"
```

## Build something

```bash
bitbake qnx-hello        # a QNX aarch64 binary, compiled with qcc
bitbake qnx-ifs-hello    # a bootable IFS containing it, assembled with mkifs
```

Artifacts land in `tmp/deploy/images/qnx-aarch64le/`:

| File | What it is |
| --- | --- |
| `qnx-hello.ifs` | the image |
| `qnx-hello.build` | the **generated** mkifs build file — read this when you cannot work out why something is or is not in the image |
| `procnto-*.sym`, `startup-*.sym` | symbol files for source-level debugging |

## Check it worked, without hardware

```bash
cd tmp/deploy/images/qnx-aarch64le

# A QNX binary, not a Linux one. The giveaway is the interpreter:
file qnx-hello                     # ... interpreter /usr/lib/ldqnx-64.so.2

# What is actually inside the image
dumpifs qnx-hello.ifs

# ...including permissions and ownership
dumpifs -v qnx-hello.ifs | grep -A1 bin/qnx-hello
```

`dumpifs` comes from the SDP, so `$QNX_HOST/usr/bin` needs to be on your `PATH`, or invoke
it by full path.

## Check the dependency tracking

This is the part that justifies the whole exercise, so it is worth seeing once:

```bash
# edit any source file of qnx-hello, then rebuild only the IMAGE
bitbake qnx-ifs-hello
```

The application recompiles, restages, and mkifs reruns — without anything telling bitbake
that the C file feeds the image. In a makefile-driven QNX build this is the part that
requires scraping `.build` files with `grep`/`sed`.

## First build is slow, later ones are not

The first invocation builds about fifteen native helper tools (`pseudo`, `quilt`, `patch`,
`m4`, …). They come from sstate afterwards. Crucially it does **not** build Yocto's cross
toolchain: `binutils-cross`, `gcc-cross` and libc are never needed, because the compiler
comes from the SDP.

## Where to go next

- [variables.md](variables.md) — every variable, with defaults
- [cookbook.md](cookbook.md) — worked examples: applications, libraries, drivers, images
