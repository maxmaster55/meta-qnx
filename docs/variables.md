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
- [Meson projects](#meson-projects)
- [Prebuilt OSS packages](#prebuilt-oss-packages) — `.apk` files from repo.oss.qnx.com
- [Application sources](#application-sources) — fetch from git, or build a working tree in place
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
`qnx-src` in local mode (see [Application sources](#application-sources)). Recipes that
need it are skipped when it is unset, so the layer still works without it.

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

### `QNX_CMAKE_SYSTEM_NAME`, `QNX_CMAKE_SYSTEM_VERSION`, `QNX_CMAKE_SYSTEM_PROCESSOR`

**Defaults:** *(empty — armed per recipe)*, `800`, `aarch64le`

Set by `qnx-toolchain.bbclass` only, and only for CMake recipes coming from a normal Yocto
layer. `qnx-sdp` recipes do not need them: `qnx-cmake.bbclass` writes its own toolchain
file.

oe-core's `cmake.bbclass` derives `CMAKE_SYSTEM_NAME` from `HOST_OS`, which stays `linux`
here, and its `oecmake_map_compiler()` keeps only `argv[0]` of `CC` — dropping the
`-V${QNX_VARIANT}` that selects the target, leaving bare `qcc`, which builds **x86-64**.
Neither produces an error; both produce a working build of the wrong thing. The class
therefore appends corrective `set()` lines to the generated `toolchain.cmake`, the same way
oe-core's own `cmake-qemu.bbclass` does:

| Written | Why |
| --- | --- |
| `CMAKE_SYSTEM_NAME` | loads `Platform/QNX.cmake`; stops projects compiling Linux branches |
| `CMAKE_SYSTEM_VERSION` / `_PROCESSOR` | what a project tests to identify QNX 8 / aarch64le |
| `CMAKE_C_COMPILER_TARGET`, `CMAKE_CXX_COMPILER_TARGET` | becomes `-V${QNX_VARIANT}` via QCC's `CMAKE_<LANG>_COMPILE_OPTIONS_TARGET` |
| `CMAKE_SYSROOT` | the SDP, not `RECIPE_SYSROOT`; QCC emits it as `-Wc,-isysroot,`, so it does not displace `qcc`'s own |
| `CMAKE_FIND_ROOT_PATH` | *appended*, keeping the OE sysroot entries where a recipe's `DEPENDS` land |
| `CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER` | `qcc` and `ntoaarch64-ar` are on `PATH`, not under a find root |

`QNX_CMAKE_SYSTEM_NAME` is empty by default and set to `QNX` by the class's anonymous
function. That empty default is the guard: this class is applied through global `INHERIT`,
so the toolchain-file append is defined for every CMake recipe in the build, including
`cmake-native`, and does nothing unless the variable is set. A recipe needing more than the
table above (extra find roots, `CMAKE_TRY_COMPILE_TARGET_TYPE`) sets it in its own
`EXTRA_OECMAKE`.

### `QNX_ELF_CHECK`, `QNX_ELF_MACHINE`

**Defaults:** `1` and `183` (EM_AARCH64)

After `do_install`, every ELF file in the stage tree is checked against the expected
`e_machine`. A build system that ignored `${CC}` — a makefile hardcoding `gcc`, a configure
step finding the host compiler — produces x86-64 Linux binaries that stage, link and mkifs
without complaint and fail only on the board; this turns that into a build error naming the
file. Set `QNX_ELF_CHECK = "0"` in a recipe that legitimately stages foreign ELFs. A
machine conf for another architecture overrides `QNX_ELF_MACHINE` alongside
`QNX_PROCESSOR`.

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

### `QNX_IFS_STARTUP_AFTER`

**Default:** `""`

Recipes whose startup commands must run before this one. Works like systemd's `After=`:
the image assembler topologically sorts all startup fragments, placing this recipe's
command after every recipe named here. Dependencies on recipes not present in the image
are silently ignored, so a recipe can safely name optional prerequisites.

Recipes with no `AFTER` constraints are ordered by their position in `QNX_IFS_INSTALL`,
which is also the tiebreak when the dependency graph does not force an order.

```bitbake
QNX_IFS_STARTUP_AFTER = "my-driver my-resmgr"
```

A cycle is a hard error.

### `QNX_IFS_STARTUP_WAITFOR`

**Default:** `""`

Space-separated paths this component provides. Emits `waitfor <path> <timeout>` after the
command.

**Ordering alone is not enough.** The startup script issues commands in order, but a driver
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

**Defaults:** `usr/include include` and `.a .la .pc .h .hpp .cmake`

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

### `QNX_IMAGE_HARVEST_DIRS`, `QNX_IMAGE_SOURCE_STYLE`, `QNX_IMAGE_SOURCE_PREFIX`

*Set by a class, not by a recipe.* The two ways an installed tree becomes image entries.
Everything above in this section is identical for both; these are the difference.

| | `qnx-sdp` recipes | stock recipes (`qnx-toolchain`) |
| --- | --- | --- |
| `QNX_IMAGE_HARVEST_DIRS` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}` | *(empty — all of `${D}`)* |
| `QNX_IMAGE_SOURCE_STYLE` | `search` | `sysroot` |

`search` names a source by bare basename and lets `mkifs` resolve it against the search
path `-r` re-roots onto the stage tree — only files in `QNX_IFS_SEARCHABLE_DIRS` can be
named this way. `sysroot` names an absolute path built from `QNX_IMAGE_SOURCE_PREFIX`
(default `@QNX_IFS_SYSROOT@`, expanded by the installing image), so any location works.
See [Reusing normal Yocto layers](reusing-layers.md).

---

## Packagegroups

`inherit qnx-packagegroup`. A recipe that builds nothing and exists to be a name for a set
of other recipes, so two images cannot drift apart about what they share. See
[Sharing between images](sharing-between-images.md).

### `QNX_PACKAGEGROUP_INSTALL`

**Default:** `""`

The members. They become `DEPENDS`, and the list is written to
`${QNX_IFS_DROPIN_DIR}/${PN}.install`, which `qnx-ifs.bbclass` reads to expand the group
wherever it is installed. Groups may list other groups.

```bitbake
inherit qnx-packagegroup
QNX_PACKAGEGROUP_INSTALL = "vsomeip commonapi-core commonapi-someip boost"
```

---

## Image recipes

### `QNX_IFS_INSTALL`

**Default:** `""`

Recipes to install into the image — the direct analogue of `IMAGE_INSTALL`. Becomes
`DEPENDS` automatically. **This is the only line that changes when you add an application.**

A name that contributes nothing warns (typo, or a recipe that never installed into the
stage tree).

### `QNX_IFS_STARTUP_DISABLE`

**Default:** `""`

Recipes whose startup commands are suppressed in this image. The recipe's files are still
installed; only its startup script lines are dropped. Use this when you want a recipe's
binaries or libraries in the image but do not want it started automatically at boot.

```bitbake
QNX_IFS_STARTUP_DISABLE = "qnx-sysinfo"
```

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
| `@QNX_IFS_STARTUP@` | startup lines, topologically sorted by `AFTER` dependencies |

bitbake's `${...}` is deliberately **not** used for this: mkifs build files use `${...}`
for their own variables (`${PROCESSOR}`, `${QNX_TARGET}`), and expanding those would
corrupt them.

`@QNX_IFS_SYSROOT@` is the third generated-ish one: it is the image's `RECIPE_SYSROOT`,
and it is what a drop-in fragment from a stock Yocto recipe uses to name its files by
absolute path. It exists because that path belongs to the image, not to the recipe that
wrote the fragment.

> **Expansion is textual.** Never name a marker inside a comment — it is substituted
> there too, and `mkifs` reports `Improper filename specification` on a line you thought
> was prose.

### `#include` and `QNX_TEMPLATE_INCLUDE_PATH`

**Default:** `""` (each layer appends `${LAYERDIR}/files/ifs` in `conf/layer.conf`)

A template may pull in a shared fragment by name:

```
#include qnx-boot.build.inc
```

resolved against the including file's own directory first, then
`QNX_TEMPLATE_INCLUDE_PATH`. This is how the host and guest images share their boot
header, startup preamble and base utilities instead of being two copies of one file — see
[Sharing between images](sharing-between-images.md).

The `#` is deliberate: `mkifs` reads the line as a comment, so a template with includes is
still a valid build file on its own. Editing a fragment rebuilds the images that use it
(`do_generate_buildfile[file-checksums]`).

> **A fragment included inside a `[+script]` block must contain no braces, even in a
> comment.** `mkifs` does not strip comments there, so a stray `}` ends the script early
> and the rest is read as file records — classically `Host file 'nto' not available`.

---

## Disk images

`inherit qnx-disk`. Produces a single `.img` you can write straight to an SD card:
a FAT boot partition (`mkfatfsimg`) and an optional pre-built data partition,
wrapped in an MBR (`diskimage`).

The data partition is always a `qnx-rootfs` recipe's deployed image — `qnx-disk`
never runs `mkqnx6fsimg` itself. This means every QNX6 filesystem goes through
one code path (`qnx-rootfs.bbclass`), and its sizing, inode count and content
injection (`QNX_ROOTFS_EXTRA`) are configured on the rootfs recipe, not the disk.

### Sizes

Each takes a byte count with an optional K/M/G suffix, or `auto`.

| Variable | Default | Marker in template |
| --- | --- | --- |
| `QNX_DISK_BOOT_SIZE` | `auto` | `@QNX_DISK_BOOT_SECTORS@` |
| `QNX_DISK_SIZE` | `auto` | `@QNX_DISK_CYLINDERS@` |

`auto` for the **boot partition** measures the files its build file references,
plus inline `{ }` bodies, and adds `QNX_DISK_SLACK_PERCENT` over a floor. `auto`
for the **disk** sums the partition images actually produced, so it is exact
rather than estimated.

An explicit `QNX_DISK_SIZE` smaller than its contents is a hard error naming both
numbers, rather than a corrupt image.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_DISK_SLACK_PERCENT` | `25` | headroom added to the auto-sized boot partition |
| `QNX_DISK_BOOT_MIN` | `32M` | floor for the boot partition |
| `QNX_DISK_RESERVED` | `1M` | space before the first partition, for MBR/IPL |

### Layout and templates

| Variable | Default |
| --- | --- |
| `QNX_DISK_NAME` | `${PN}` |
| `QNX_DISK_BOOT_TEMPLATE` | `${S}/${QNX_DISK_NAME}-boot.build.in` |
| `QNX_DISK_CFG_TEMPLATE` | `${S}/${QNX_DISK_NAME}-disk.cfg.in` |
| `QNX_DISK_INSTALL` | `""` — image recipes whose `.ifs` this disk needs |
| `QNX_DISK_DATA_IMG` | `""` — path to a pre-built QNX6 image for the data partition; leave empty for a boot-only disk |
| `QNX_DISK_SEARCH_ROOTS` | `${B} ${DEPLOY_DIR_IMAGE}` — where auto-sizing resolves bare names |

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
`part-*.img`, and the generated `boot.build` / `disk.cfg` — which are what you
read when a disk does not boot.

```bash
sudo bmaptool copy qnx-host-disk.img /dev/sdX     # with the block map
sudo dd if=qnx-host-disk.img of=/dev/sdX bs=4M conv=fsync status=progress
```

---

## QNX6 filesystem images (rootfs)

`inherit qnx-rootfs`. Produces a **bare QNX6 filesystem image** (`mkqnx6fsimg`) — no
partition table, no MBR. This is the single class for every QNX6 filesystem, whether it is
a guest data disk (mounted with `mount -t qnx6 /dev/vblk0 /`) or a host disk's data
partition (wrapped into an MBR by `qnx-disk` via `QNX_DISK_DATA_IMG`).

Like an image, a rootfs lists what it carries; the names become `DEPENDS` and their staged
files arrive in the sysroot, reachable in the template under `@QNX_ROOTFS_SYSROOT@`:

```bitbake
QNX_ROOTFS_INSTALL = "qt-cluster qnx-screen-virtio"
```

Unlike an IFS there is **no auto-derived file list** — a rootfs maps staged trees onto
specific target paths the guest's boot config depends on (`LD_LIBRARY_PATH`, screen's
search dirs), so those mappings are stated in the template, exactly as the project's own
`rootfs.build` is written by hand.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_ROOTFS_INSTALL` | `""` | recipes whose staged files ride on the disk — becomes `DEPENDS` |
| `QNX_ROOTFS_NAME` | `${PN}` | basename of the `.img` and generated `.build` |
| `QNX_ROOTFS_TEMPLATE` | `${S}/${QNX_ROOTFS_NAME}.build.in` | the mkqnx6fsimg template |
| `QNX_ROOTFS_SYSROOT` | `${RECIPE_SYSROOT}${QNX_STAGE_DIR}` | stage tree the template names sources under, as `@QNX_ROOTFS_SYSROOT@` |
| `QNX_ROOTFS_SIZE` | `auto` | `auto` grows from `QNX_ROOTFS_MIN` until it fits; an explicit K/M/G size never grows |
| `QNX_ROOTFS_MIN` | `256M` | floor an auto-sized image starts from |
| `QNX_ROOTFS_INODES` | `20000` | preallocated at format time — a hard ceiling on file count, available as `@QNX_ROOTFS_INODES@` |
| `QNX_ROOTFS_BLKSIZE` | `4096` | `@QNX_ROOTFS_BLKSIZE@` |
| `QNX_ROOTFS_EXTRA` | `""` | raw records for content with no staged file behind it, multi-line via literal `\n` — this is how a layer adds content to a rootfs defined elsewhere |

Template markers: `@QNX_ROOTFS_SECTORS@` (the computed size — put it in `[num_sectors=...]`
at the top), `@QNX_ROOTFS_INODES@`, `@QNX_ROOTFS_BLKSIZE@`, `@QNX_ROOTFS_SYSROOT@`, and
`@QNX_ROOTFS_EXTRA@`. Deployed as `${QNX_ROOTFS_NAME}.img` plus the generated `.build`.

A host disk wraps a rootfs image as its data partition by setting `QNX_DISK_DATA_IMG` to
the deployed path and adding a task dependency on `do_deploy`. A guest layer injects its
artifacts into the host's data partition via a bbappend on the rootfs recipe that sets
`QNX_ROOTFS_EXTRA`.

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
| `QNX_SDP_LOCKFILE` | `""` | resolved `<id>/<version>` snapshot. Features match **against this**, so they cannot select a package it does not list |
| `QNX_SDP_EXTRA_PACKAGES` | `""` | packages to install regardless of features, as `<id>` or `<id>/<version>`. The only way to install one not yet in the lockfile |
| `QNX_SDP_PACKAGE_VERSION[id]` | *(unset)* | pin one package to a version; beats both the lockfile and `QNX_SDP_EXTRA_PACKAGES` |
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

`cmake` and `ninja` come from the host, allowed through bitbake's sanitized `PATH` by the
`HOSTTOOLS` addition in meta-qnx's `conf/layer.conf` (it must be global config — `HOSTTOOLS`
symlinks are created once at cooker startup, before any class is inherited).

---

## Meson projects

`inherit qnx-meson` (which inherits `qnx-sdp`). Generates a cross file from the SDP paths
— so it never goes stale relative to `QNX_SDP_ROOT` — and synthesises pkg-config metadata
for SDP libraries that ship as plain `.so` files without any, which is what lets a meson
project's `dependency('egl')` succeed.

The compilers are the GNU-style drivers (`ntoaarch64-gcc`), not `qcc`: meson probes the
compiler and does not understand `qcc -V`.

| Variable | Default | Notes |
| --- | --- | --- |
| `QNX_MESON_CROSS` | `${B}/qnx-cross.ini` | generated cross file |
| `QNX_MESON_CC` / `QNX_MESON_CXX` | `ntoaarch64-gcc` / `ntoaarch64-g++` | names inside `${QNX_HOST}/usr/bin` |
| `QNX_MESON_AR` / `QNX_MESON_STRIP` | `ntoaarch64-ar` / `ntoaarch64-strip` | |
| `QNX_MESON_SYSTEM` | `qnx` | `[host_machine]` system |
| `QNX_MESON_CPU_FAMILY` / `QNX_MESON_CPU` | `aarch64` / `aarch64` | |
| `QNX_MESON_ENDIAN` | `little` | |
| `QNX_MESON_C_ARGS` | `'-D_QNX_SOURCE', '-include', '…/sys/neutrino.h', '-DHAVE_TIMESPEC_GET=1'` | meson list syntax |
| `QNX_MESON_LINK_ARGS` | `""` | |
| `QNX_MESON_ARGS` | `""` | extra `meson setup` arguments |
| `QNX_MESON_SDP_PCFILES` | `libdrm egl gl glesv2 gbm` entries | `<name>:<version>:<libs>[:<cflags>]` — SDP libraries to write `.pc` files for |

Installs use `--prefix ${QNX_STAGE_DIR} --libdir ${QNX_PROCESSOR}/lib --includedir
usr/include`, so output lands in the stage-tree shape automatically.

`PKG_CONFIG_SYSROOT_DIR` is cleared: the synthesised `.pc` files hold real absolute paths,
and OE's sysroot prefixing would rewrite them into paths that exist nowhere.

---

## Autotools / `./configure` projects

`inherit qnx-autotools` (which inherits `qnx-sdp`). The third build-system driver, for the
`./configure` + `make` family that dominates meta-openembedded and oe-core. Drives
configure with qcc and the stage-tree install directories; `do_compile`/`do_install` are
`oe_runmake` and `oe_runmake DESTDIR=${D} install`.

Verified against **unmodified upstream zlib**: a portable configure library builds for QNX
with no code patches — see `recipes-example/zlib` and the
[cookbook](cookbook.md#a-library-reused-from-upstream-autotools). The class removes the
toolchain plumbing, not the portability work: code that assumes Linux/glibc still needs the
same porting a hand build would.

| Variable | Default | Notes |
| --- | --- | --- |
| `QNX_CONFIGURE_HOST` | `aarch64-unknown-nto-qnx8.0.0` (from `QNX_TOOL_PREFIX`) | `--host` triplet that puts autoconf in cross mode; set `""` for a hand-rolled configure that rejects it |
| `QNX_CONFIGURE_HOST_ARGS` | `--build=<sys> --host=<host>`, or empty when the host is cleared | the cross-mode pair, as one switch |
| `QNX_AUTOTOOLS_DIRS` | `--bindir` `--sbindir` `--libdir` `--includedir` mapped onto the stage tree | override wholesale for a configure that rejects one of them |
| `QNX_CONFIGURE_SCRIPT` | `${S}/configure` | for a configure kept in a subdirectory |
| `EXTRA_OECONF` | `""` (+ OE's `${DISABLE_STATIC}`) | extra configure args; clear `DISABLE_STATIC` for a configure that rejects `--disable-static` |

Like `qnx-meson`, `PKG_CONFIG_SYSROOT_DIR` is cleared and `PKG_CONFIG_LIBDIR` points at the
stage tree, so a library built by another qnx recipe is found by `pkg-config`.

This class is deliberately not built on OE's `autotools.bbclass`, which assumes Yocto's
cross-toolchain, `autoconf-native`/`gnu-configize` and packaging — all of which `qnx-sdp`
switches off.

---

## Prebuilt OSS packages

`inherit qnx-apk`. Fetches a prebuilt `.apk` from QNX's OSS repository
(repo.oss.qnx.com) and stages its payload; see the
[cookbook](cookbook.md#a-prebuilt-package-from-qnxs-oss-repository) for the two-line
recipe pattern and where the checksum comes from.

Find a package, and get a paste-ready recipe for it, with
`bitbake -c search_oss qnx-sdp` — see [sdp.md](sdp.md#bitbake--c-search_oss-qnx-sdp).

| Variable | Default | Notes |
| --- | --- | --- |
| `QNX_APK_NAME` | `${BPN}` | package name in the repository |
| `QNX_APK_VERSION` | `${PV}` | from the recipe filename |
| `QNX_OSS_REPO` | `https://repo.oss.qnx.com` | set in `conf/layer.conf`, so the class and the search task cannot drift |
| `QNX_OSS_CHANNEL` | `8.0.4/qnx-extra` | the one per-recipe fact; also served: `8.0.3/core`, `8.0.3/extra`, `8.0.4/qnx-core` |
| `QNX_OSS_ARCH` | `aarch64` | set in `conf/layer.conf` |
| `QNX_OSS_SEARCH` | `""` | substring filter for `-c search_oss` |
| `QNX_OSS_SEARCH_CHANNELS` | the four channels QNX serves | which indexes `-c search_oss` reads |
| `QNX_APK_DEST` | `${QNX_STAGE_DIR}/${QNX_PROCESSOR}` | an apk is target-rooted; override `do_install` for a different layout |
| `LICENSE_FLAGS` | `qnx-non-commercial` | most packages are `LicenseRef-QDL-Non-Commercial`; accept with `LICENSE_FLAGS_ACCEPTED` |

---

## Application sources

`inherit qnx-src`. One class, two modes:

**Fetch from git** (the default) — the recipe names its repository and tracks the branch
head, so a build picks up whatever was pushed last:

```bitbake
QNX_SRC_REPO = "git://github.com/you/thing.git;protocol=https;branch=main"
```

**Build a working tree in place** — point `QNX_SRC_LOCAL` at a checkout and the recipe
builds that tree via `externalsrc` instead of fetching; no commit needed to see a change.
Set it per-recipe, or globally in `local.conf`:

```bitbake
QNX_SRC_LOCAL:pn-frame-router = "/path/to/checkout"
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_SRC_REPO` | `""` | git URL, bitbake fetcher syntax — required unless `QNX_SRC_LOCAL` is set |
| `QNX_SRC_BRANCH` | `main` | |
| `QNX_SRC_REV` | `${AUTOREV}` | pin to a commit for a reproducible, offline build |
| `QNX_SRC_SUBDIR` | `""` | this application's directory, for a repo of many apps |
| `QNX_SRC_LOCAL` | `""` | checkout to build in place instead of fetching |
| `EXTERNALSRC_BUILD` | `${EXTERNALSRC}/build` | set to `${WORKDIR}/build` for out-of-tree build systems |
| `EXTERNALSRC_SYMLINKS` | `""` | disabled, so the build does not litter someone else's repo |

**Trade-offs, both deliberate:** tracking a branch head (`AUTOREV`) needs the network at
parse time and two builds a minute apart can differ — pin `QNX_SRC_REV` for CI. A local
working tree has no revision to hash, so those recipes lose sstate and rebuild every time —
right while editing, wrong for CI, which is why fetching is the default.

`meta-qnx-hyp/conf/qnx-project-repo.inc` layers project policy on top: every recipe built
from the hypervisor monorepo shares one `QNX_PROJECT_REPO` / `QNX_PROJECT_BRANCH` /
`QNX_PROJECT_REV`, and setting `QNX_PROJECT_SRC` flips them all to local working-tree mode
at once.

---

## Tasks

| Task | Class | Does |
| --- | --- | --- |
| `do_generate_toolchain_file` | `qnx-cmake` | writes the CMake toolchain file |
| `do_generate_meson_cross` | `qnx-meson` | writes the cross file and the SDP `.pc` files |
| `do_configure`/`do_compile`/`do_install` | `qnx-autotools` | runs `./configure`, `make`, `make install` with qcc |
| `do_extract_apk` | `qnx-apk` | unpacks the `.apk`'s concatenated tar streams |
| `do_search_oss` | `qnx-sdp` recipe | lists repo.oss.qnx.com packages and prints a paste-ready recipe |
| `qnx_sdp_write_ifs_dropin` | `qnx-sdp` | `do_install` postfunc; writes the recipe's IFS fragments |
| `qnx_sdp_check_staged_elfs` | `qnx-sdp` | `do_install` postfunc; rejects staged non-target ELFs |
| `do_generate_buildfile` | `qnx-ifs` | expands the template into the real build file |
| `do_mkifs` | `qnx-ifs` | runs mkifs |
| `do_dumpifs` | `qnx-ifs` | prints the built image's contents (`bitbake -c dumpifs <image>`) |
| `do_deploy` | `qnx-ifs` | copies `.ifs`, generated `.build` and `.sym` files to the deploy dir |
| `do_generate_diskfiles` | `qnx-disk` | expands the boot partition template, auto-sizing from contents |
| `do_generate_diskcfg` | `qnx-disk` | sizes the disk from the partition images actually built |
| `do_generate_rootfs_buildfile` | `qnx-rootfs` | expands the rootfs template with the computed size |
| `do_compile` | `qnx-rootfs` | runs mkqnx6fsimg, growing the image until it fits |

`qnx-disk` and `qnx-rootfs` share `qnx_build_fsimg` in `qnx-sdp.bbclass` for building
filesystem images with grow-on-overflow retry. `qnx-disk` uses it for `mkfatfsimg` (boot
partition); `qnx-rootfs` uses it for `mkqnx6fsimg` (every QNX6 filesystem). A disk's data
partition is always a deployed `qnx-rootfs` image — `qnx-disk` never calls `mkqnx6fsimg`
itself.

Useful invocations:

```bash
bitbake -c dumpifs qnx-ifs-hello              # build if needed, print the contents
bitbake -c generate_buildfile qnx-ifs-hello   # generate without running mkifs
bitbake -e qnx-hello | grep '^CC='            # what a recipe will actually run
bitbake -g qnx-hello && cat pn-buildlist      # what it drags in

# What open-source packages can I get, and what recipe do I write for one?
echo 'QNX_OSS_SEARCH = "dbus"' > oss-search.conf
bitbake -c search_oss qnx-sdp -R oss-search.conf
```
