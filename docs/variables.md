# Variable reference

Every variable the layer defines, grouped by where you would set it. Defaults are exact.

- [Build configuration](#build-configuration) — `local.conf`
- [Machine](#machine) — CPU and toolchain identity
- [SDP location](#sdp-location)
- [Staging paths](#staging-paths) — where a recipe installs
- [Application recipes](#application-recipes) — what a recipe contributes to an image
- [Image recipes](#image-recipes) — what an image is
- [Disk images](#disk-images) — a flashable .img
- [SDP packages](#sdp-packages) — see also [sdp.md](sdp.md)
- [CMake projects](#cmake-projects)
- [Working-tree builds](#working-tree-builds)
- [Tasks](#tasks)

---

## Build configuration

Set these in `conf/local.conf`.

### `QNX_SDP_ROOT`

**Default:** `${TOPDIR}/qnx-sdp`

Path to the QNX SDP install. Used **strictly read-only** by every build; only
`bitbake -c install_sdp qnx-sdp` ever writes to it.

Defaults inside the build directory in the same spirit as `DL_DIR` and `SSTATE_DIR`, so a
fresh build directory works with no configuration and `install_sdp` creates an SDP there.
Point it at an existing install to use one you already have:

```bitbake
QNX_SDP_ROOT = "/home/you/qnx800"
```

Recipes are **skipped** with an explanatory message when the path does not contain a
`target/qnx`. That is deliberate: a missing SDP should say so by name, not surface as
`qcc: command not found` halfway through `do_compile`.

The default lives in `conf/layer.conf` rather than a class, so that both the build classes
and the SDP installer — which must work *before* any SDP exists — see the same value.

### `QNX_PROJECT_SRC`

**Default:** `""` (also set in `conf/layer.conf`)

Root of a working tree containing application sources, for recipes inheriting
`qnx-project-src`. Recipes that need it are skipped when it is unset, so the layer still
works without it.

---

## Machine

Set in `conf/machine/*.conf`. The shipped machine is `qnx-aarch64le`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_PROCESSOR` | `aarch64le` | QNX's name for the target. Used as `$PROCESSOR`/`$ARCH` for mkifs, and as the subdirectory name inside `$QNX_TARGET` and the stage tree. |
| `QNX_VARIANT` | `gcc_ntoaarch64le` | `qcc -V` variant. Run `qcc -V` to list what your SDP offers. |
| `QNX_TOOL_PREFIX` | `aarch64-unknown-nto-qnx8.0.0-` | Prefix for the binutils in `$QNX_HOST/usr/bin`. |

To target another architecture, copy the machine file and change these three.

---

## SDP location

Derived from `QNX_SDP_ROOT`; override only for an unusual layout.

| Variable | Default |
| --- | --- |
| `QNX_HOST` | `${QNX_SDP_ROOT}/host/linux/x86_64` |
| `QNX_TARGET` | `${QNX_SDP_ROOT}/target/qnx` |
| `QNX_CONFIGURATION` | `$HOME/.qnx` |
| `QNX_CONFIGURATION_EXCLUSIVE` | `${QNX_CONFIGURATION}` |

All four are exported into the task environment, and `$QNX_HOST/usr/bin` plus
`${QNX_SDP_ROOT}/host/common/bin` are prepended to `PATH`.

`QNX_CONFIGURATION` is where `qcc` reads its target definitions and licence. It is pinned
explicitly rather than inherited from the caller's environment so builds do not depend on
who started them.

---

## Staging paths

Read these in `do_install`; do not redefine them.

| Variable | Value | Goes into |
| --- | --- | --- |
| `QNX_STAGE_DIR` | `/qnx-stage` | — (the root) |
| `QNX_STAGE_BINDIR` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}/bin` | image + sysroot |
| `QNX_STAGE_SBINDIR` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}/sbin` | image + sysroot |
| `QNX_STAGE_LIBDIR` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}/lib` | image + sysroot |
| `QNX_STAGE_USRLIBDIR` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}/usr/lib` | image + sysroot |
| `QNX_STAGE_INCLUDEDIR` | `${QNX_STAGE_DIR}/usr/include` | **sysroot only** |

The tree mirrors `$QNX_TARGET`, which is what `mkifs -r` expects *and* what a compiler
wants — so one tree serves both roles. Headers and static libraries never enter an image.

### `QNX_SYSROOT_CPPFLAGS`, `QNX_SYSROOT_LDFLAGS`

**Defaults:** `-I${RECIPE_SYSROOT}${QNX_STAGE_INCLUDEDIR}` and
`-L${RECIPE_SYSROOT}${QNX_STAGE_LIBDIR} -L${RECIPE_SYSROOT}${QNX_STAGE_USRLIBDIR}`

Appended to `CFLAGS`/`CXXFLAGS`/`LDFLAGS`. This is what makes `DEPENDS` on another QNX
recipe give you its headers and libraries.

### Toolchain variables

Set by `qnx-sdp.bbclass`; listed so you know what your build system will be handed.

| Variable | Value |
| --- | --- |
| `CC` | `qcc -V${QNX_VARIANT}` |
| `CXX` | `q++ -V${QNX_VARIANT}` |
| `CPP` | `qcc -V${QNX_VARIANT} -E` |
| `LD` | `qcc -V${QNX_VARIANT}` |
| `AR` `NM` `RANLIB` `STRIP` `OBJCOPY` `OBJDUMP` `READELF` | `${QNX_TOOL_PREFIX}<tool>` |
| `CFLAGS` / `CXXFLAGS` | `-O2 -Wall -Wextra` (+ sysroot flags) |
| `LDFLAGS` | *(empty)* (+ sysroot flags) |

`TARGET_CC_ARCH`, `TOOLCHAIN_OPTIONS`, `DEBUG_PREFIX_MAP`, `SECURITY_CFLAGS` and
`SECURITY_LDFLAGS` are cleared: Yocto's defaults carry `--sysroot=` and hardening options
aimed at its own gcc, several of which `qcc` rejects outright.

---

## Application recipes

What a recipe contributes to any image that installs it.

### `QNX_IFS_STARTUP_CMD`

**Default:** `""`

Command(s) to run from the image's startup script. Empty means the recipe ships files but
starts nothing.

```bitbake
QNX_IFS_STARTUP_CMD = "my-daemon &"
```

### `QNX_IFS_STARTUP_PRIORITY`

**Default:** `500` · **Range:** any non-negative integer (non-numeric is a hard error)

Position in the boot sequence; lower runs earlier. Conventional bands:

| Priority | For |
| --- | --- |
| 100 | hardware drivers, anything providing a `/dev` entry |
| 300 | resource managers and services built on those |
| 500 | applications (default) |
| 700 | anything wanting the system fully up |

Equal priorities fall back to `QNX_IFS_INSTALL` order.

### `QNX_IFS_STARTUP_WAITFOR`

**Default:** `""`

Space-separated paths this component provides. Emits `waitfor <path> <timeout>` after the
command.

**Priority alone is not enough.** The startup script issues commands in order, but a driver
started with `&` forks and returns immediately, so the next command can run before the
device exists. `waitfor` is what actually blocks. Declared by whoever *provides* the path,
so everything later in the sequence is safe without knowing who to wait for.

Setting this without `QNX_IFS_STARTUP_CMD` warns — nothing would ever create the path.

### `QNX_IFS_STARTUP_WAITFOR_TIMEOUT`

**Default:** `5` (seconds)

### `QNX_IFS_ATTR[<basename>]`

**Default:** *(none)*

mkifs record attributes, passed through verbatim. Every attribute mkifs supports is
reachable — `uid`, `gid`, `perms`, `dperms`, `type`, `prefix`, `search`, `data`, `filter`,
`cksum`, `sha256`, `sha512`, `chain`, `module`, `mtime`, `keepsection`, `argv0`, `autoso`,
and any a future SDP adds.

```bitbake
QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"
QNX_IFS_ATTR[bigfile]  = "data=copy"
```

> **Keys are basenames, not paths.** bitbake varflag names may only contain
> `[a-zA-Z0-9-_+.@]`, so `QNX_IFS_ATTR[/sbin/rpi_gpio]` is a **parse error**, not a lookup
> that fails quietly.

A key matching no staged file warns.

### `QNX_IFS_DEFAULT_ATTR`

**Default:** `""`

Attributes applied to every entry this recipe contributes, before any per-entry value.

```bitbake
QNX_IFS_DEFAULT_ATTR = "uid=0 gid=0"
```

### `QNX_IFS_DEST[<basename>]`

**Default:** *(none)*

Override where a staged file lands. Key is the basename, value the full destination path.

```bitbake
QNX_IFS_DEST[myapp] = "/proc/boot/myapp"
```

### `QNX_IFS_EXTRA_ENTRIES`

**Default:** `""`

Raw mkifs lines, for entries with no staged file behind them: symlinks into `/tmp` or
`/dev`, inline config bodies, `[search=...]` for unusual locations.

Separate multiple entries with a **literal `\n`**. bitbake does not process escape
sequences in variable values, and a line continuation collapses to a space, so there is
otherwise no way to express a multi-line value. The class translates it.

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[type=link] /etc/foo.conf=/tmp/foo.conf\n[type=link] /var/run=/tmp"
```

### `QNX_IFS_AUTO_ENTRIES`

**Default:** `1` · **Values:** `1` | `0`

`0` disables deriving entries from staged files; you then declare everything through
`QNX_IFS_EXTRA_ENTRIES`.

### `QNX_IFS_SEARCHABLE_DIRS`

**Default:** `bin sbin lib usr/bin usr/sbin usr/lib lib/dll boot/sys`

Directories mkifs's search path covers, and therefore the ones whose contents can be
referenced by bare name. A staged file outside these warns rather than vanishing silently.

Note this is a flat list: `lib/dll` is searched but `lib/dll/pci` is **not**, which is why
nested modules are referenced as `pci/pci_slog2.so`.

### `QNX_IFS_EXCLUDE_DIRS`, `QNX_IFS_EXCLUDE_SUFFIXES`

**Defaults:** `usr/include include` and `.a .la .pc .h .hpp`

Staged content that belongs to the sysroot and never to an image. Excluded silently — this
is not a mistake worth warning about.

### `QNX_IFS_DROPIN_DIR`

**Default:** `${QNX_STAGE_DIR}/ifs.d`

Where per-recipe fragments are written (`<pn>.files`, `<pn>.startup`). Informational; you
should not need to change it.

### `QNX_IFS_ATTR_SIG`, `QNX_IFS_DEST_SIG`

*Internal.* Serialised forms of the `QNX_IFS_ATTR` / `QNX_IFS_DEST` varflags.

Varflags do not participate in task signatures, so without these, editing an attribute
would not invalidate `do_install` and the change would silently never reach the image. You
will see them in `bitbake -e`; do not set them.

---

## Image recipes

### `QNX_IFS_INSTALL`

**Default:** `""`

Recipes to install into the image — the direct analogue of `IMAGE_INSTALL`. Becomes
`DEPENDS` automatically. **This is the only line that changes when you add an application.**

A name that contributes nothing warns (typo, or a recipe that never installed into the
stage tree).

### `QNX_IFS_NAME`

**Default:** `${PN}`

Basename of the image. Also passed to `mkifs -a`, so it names the `.sym` files.

### `QNX_IFS_TEMPLATE`

**Default:** `${S}/${QNX_IFS_NAME}.build.in`

The mkifs build-file template. Must contain `@QNX_IFS_FILES@`; missing it is a hard error,
since installed recipes would have nowhere to go.

### `QNX_IFS_BUILDFILE`

**Default:** `${B}/${QNX_IFS_NAME}.build`

The generated build file actually handed to mkifs. Also copied to the deploy directory
next to the `.ifs`.

### `QNX_IFS_ROOT` / `QNX_IFS_EXTRA_ROOTS` / `QNX_IFS_ROOTS`

**Defaults:** `${RECIPE_SYSROOT}${QNX_STAGE_DIR}` · `""` · `${QNX_IFS_ROOT} ${QNX_IFS_EXTRA_ROOTS}`

mkifs search roots, passed as repeated `-r` and searched **left to right**, before
`$QNX_TARGET`. A non-existent root is a hard error rather than a mysterious "not available".

`QNX_IFS_EXTRA_ROOTS` is how a board layer adds a BSP tree holding binaries the SDP does
not ship.

### Boot configuration

Available in templates as `@QNX_STARTUP@` and so on. Defaults describe a hypervisor
**guest**.

| Variable | Default | Host example |
| --- | --- | --- |
| `QNX_STARTUP` | `startup-armv8_fm` | `startup-bcm2712-rpi5` |
| `QNX_STARTUP_ARGS` | `-H` | `-v -u reg -a -W 5000 -Q enable,el1-host` |
| `QNX_KERNEL` | `procnto-smp-instr` | *(same)* |
| `QNX_KERNEL_ARGS` | `-v` | *(same)* |
| `QNX_IMAGE_ADDR` | `0x80000000` | `0x80000` |
| `QNX_IMAGE_VIRTUAL` | `${QNX_PROCESSOR},elf` | `${QNX_PROCESSOR},raw -compress` |
| `QNX_IFS_PATH` | `/proc/boot:/bin:/usr/bin:/sbin:/usr/sbin` | |
| `QNX_IFS_LD_LIBRARY_PATH` | `/proc/boot:/lib:/usr/lib:/lib/dll` | |

These are **image** properties, not machine properties: one aarch64le tree legitimately
produces both a host and its guests.

### toybox

QNX 8 ships no standalone `ls`, `cat`, `cp`, `uname` or `grep`. They come from `toybox`, a
multicall binary dispatching on `argv[0]`.

| Variable | Default |
| --- | --- |
| `QNX_IFS_TOYBOX` | `toybox` (source name) |
| `QNX_IFS_TOYBOX_PATH` | `/usr/bin/toybox` (destination) |
| `QNX_IFS_TOYBOX_CMDS` | 62 commands — `ls cat cp mv rm mkdir … tar gzip md5sum` |

```bitbake
QNX_IFS_TOYBOX_CMDS = ""             # leave toybox out entirely
QNX_IFS_TOYBOX_CMDS += "vi bc"       # extend the default set
```

Links use absolute targets (`/bin/ls -> /usr/bin/toybox`). The SDP docs show a bare
`=toybox`, but a symlink target without a leading slash resolves relative to the link's own
directory, so `/bin/ls` would look for a non-existent `/bin/toybox`.

### Template markers

Any `@VARIABLE@` in a template is expanded from the datastore; an unset one is a hard
error. Two are generated rather than looked up:

| Marker | Contents |
| --- | --- |
| `@QNX_IFS_FILES@` | file entries from every installed recipe, plus toybox |
| `@QNX_IFS_STARTUP@` | startup lines, ordered by priority |

bitbake's `${...}` is deliberately **not** used for this: mkifs build files use `${...}`
for their own variables (`${PROCESSOR}`, `${QNX_TARGET}`), and expanding those would
corrupt them.

---

## Disk images

`inherit qnx-disk`. Produces a single `.img` you can write straight to an SD card:
a FAT boot partition (`mkfatfsimg`), an optional QNX6 data partition
(`mkqnx6fsimg`), wrapped in an MBR (`diskimage`).

### Sizes

Each takes a byte count with an optional K/M/G suffix, or `auto`.

| Variable | Default | Marker in template |
| --- | --- | --- |
| `QNX_DISK_BOOT_SIZE` | `auto` | `@QNX_DISK_BOOT_SECTORS@` |
| `QNX_DISK_DATA_SIZE` | `auto` | `@QNX_DISK_DATA_SECTORS@` |
| `QNX_DISK_SIZE` | `auto` | `@QNX_DISK_CYLINDERS@` |

`auto` for a **partition** measures the files its build file references, plus
inline `{ }` bodies, and adds `QNX_DISK_SLACK_PERCENT` over a floor. `auto` for
the **disk** sums the partition images actually produced, so it is exact rather
than estimated.

An explicit `QNX_DISK_SIZE` smaller than its contents is a hard error naming both
numbers, rather than a corrupt image.

> The data partition is written to at runtime, so `auto` — which sizes it to its
> initial contents — is usually not what you want. Give it a real size.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_DISK_SLACK_PERCENT` | `25` | headroom added to an auto-sized partition |
| `QNX_DISK_BOOT_MIN` | `32M` | floor for the boot partition |
| `QNX_DISK_DATA_MIN` | `64M` | floor for the data partition |
| `QNX_DISK_RESERVED` | `1M` | space before the first partition, for MBR/IPL |

### Layout and templates

| Variable | Default |
| --- | --- |
| `QNX_DISK_NAME` | `${PN}` |
| `QNX_DISK_BOOT_TEMPLATE` | `${S}/${QNX_DISK_NAME}-boot.build.in` |
| `QNX_DISK_DATA_TEMPLATE` | `""` — optional; set it to add a data partition |
| `QNX_DISK_CFG_TEMPLATE` | `${S}/${QNX_DISK_NAME}-disk.cfg.in` |
| `QNX_DISK_INSTALL` | `""` — image recipes whose `.ifs` this disk needs |
| `QNX_DISK_SEARCH_ROOTS` | `${B} ${DEPLOY_DIR_IMAGE}` — where auto-sizing resolves bare names |

QNX6 format-time parameters, available as `@QNX_DISK_DATA_INODES@` and
`@QNX_DISK_DATA_BLKSIZE@`:

| Variable | Default | Notes |
| --- | --- | --- |
| `QNX_DISK_DATA_INODES` | `50000` | preallocated at format time — a hard ceiling on file count |
| `QNX_DISK_DATA_BLKSIZE` | `4096` | |

Geometry, available as `@QNX_DISK_HEADS@` and friends. The defaults make a
cylinder exactly 1 MiB, which keeps sizes on whole megabytes and partitions
aligned:

| Variable | Default |
| --- | --- |
| `QNX_DISK_HEADS` | `64` |
| `QNX_DISK_SECTORS_PER_TRACK` | `32` |
| `QNX_DISK_SECTOR_SIZE` | `512` |

### Output

`tmp/deploy/images/<machine>/` gets the disk image, a `.bmap` if `bmaptool` is
available (faster flashing; optional, and a failure only warns), the intermediate
`part-*.img`, and the generated `boot.build` / `data.build` / `disk.cfg` — which
are what you read when a disk does not boot.

```bash
sudo bmaptool copy qnx-host-disk.img /dev/sdX     # with the block map
sudo dd if=qnx-host-disk.img of=/dev/sdX bs=4M conv=fsync status=progress
```

---

## SDP packages

`inherit qnx-sdp-packages`. Full guide in [sdp.md](sdp.md).

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_QSC_CLT` | `""` | path to `qnxsoftwarecenter_clt` |
| `QNX_QSC_URL` | `https://www.qnx.com/swcenter` | repository |
| `QNX_QSC_PROFILE` | `""` | p2 profile; derived automatically when empty |
| `QNX_QSC_EXTRA_ARGS` | `-setExperimentalEnabled=true -setPolicy=conservative` | |
| `QNX_SDP_CREDENTIALS_FILE` | `$HOME/.qnx/qsc-credentials` | myQNX login, `@file` form; excluded from signatures |
| `QNX_SDP_VERSION` | `qnx800` | drives the package id prefix |
| `QNX_SDP_PKG_PREFIX` | `com.qnx.${QNX_SDP_VERSION}` | |
| `QNX_SDP_FEATURES` | `""` | feature names to install |
| `QNX_SDP_FEATURE[name]` | *(see `conf/qnx-sdp-features.inc`)* | glob patterns defining a feature |
| `QNX_SDP_LOCKFILE` | `""` | resolved `<id>/<version>` snapshot |
| `QNX_SDP_EXTRA_PACKAGES` | `""` | ids to install regardless of features |
| `QNX_SDP_EXCLUDE_PACKAGES` | `""` | id patterns to keep out |
| `QNX_SDP_REQUIRES` | `""` | packages this recipe needs; verified by `check_sdp` |
| `QNX_SDP_SEARCH` | `""` | filter for `-c search` |
| `QNX_SDP_CHECK` | `1` | whether image builds verify the SDP first |

---

## CMake projects

`inherit qnx-cmake` (which inherits `qnx-sdp`).

| Variable | Default | Notes |
| --- | --- | --- |
| `OECMAKE_GENERATOR` | `Ninja` | |
| `OECMAKE_BUILD_TYPE` | `Release` | |
| `OECMAKE_SOURCEPATH` | `${S}` | |
| `OECMAKE_INSTALL_PREFIX` | `${QNX_STAGE_DIR}` | so upstream `install()` rules land correctly |
| `OECMAKE_EXTRA_ARGS` | `""` | extra `-D` flags |
| `QNX_TOOLCHAIN_FILE` | `${B}/qnx-toolchain.cmake` | generated |

The generated toolchain file sets `CMAKE_SYSTEM_NAME QNX`, points the compilers at
`qcc`/`q++`, and puts **both** the SDP and the recipe sysroot on `CMAKE_FIND_ROOT_PATH`, so
`find_package`/`find_library` can see other recipes' output.

This class is deliberately not built on OE's `cmake.bbclass`, which assumes Yocto's
cross-toolchain, sysroot layout and a native cmake recipe — all of which `qnx-sdp` switches
off.

---

## Working-tree builds

`inherit qnx-project-src`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_PROJECT_SRC` | `""` | tree root (set in `local.conf`) |
| `QNX_APP_SUBDIR` | `""` | this recipe's directory under it — required |
| `EXTERNALSRC_BUILD` | `${EXTERNALSRC}/build` | set to `${WORKDIR}/build` for out-of-tree |
| `EXTERNALSRC_SYMLINKS` | `""` | disabled, so the build does not litter someone else's repo |

**Trade-off:** externalsrc disables sstate for these recipes, so `do_compile` runs every
time. That is right while porting; a stabilised recipe should move to a real `SRC_URI` with
a pinned revision.

---

## Tasks

| Task | Class | Does |
| --- | --- | --- |
| `do_generate_toolchain_file` | `qnx-cmake` | writes the CMake toolchain file |
| `qnx_sdp_write_ifs_dropin` | `qnx-sdp` | `do_install` postfunc; writes the recipe's IFS fragments |
| `do_generate_buildfile` | `qnx-ifs` | expands the template into the real build file |
| `do_mkifs` | `qnx-ifs` | runs mkifs |
| `do_deploy` | `qnx-ifs` | copies `.ifs`, generated `.build` and `.sym` files to the deploy dir |

Useful invocations:

```bash
bitbake -c generate_buildfile qnx-ifs-hello   # generate without running mkifs
bitbake -e qnx-hello | grep '^CC='            # what a recipe will actually run
bitbake -g qnx-hello && cat pn-buildlist      # what it drags in
```
