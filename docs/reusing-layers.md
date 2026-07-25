# Reusing recipes from normal Yocto layers

`qnx-cmake`, `qnx-meson` and `qnx-autotools` let you write a *new* QNX recipe cheaply. This
document is about the other direction: building a recipe **you did not write** — poky's own
`bzip2`, a library from `meta-openembedded` — for QNX, unmodified.

That is what `qnx-toolchain.bbclass` is for. It makes `qcc` the default toolchain for every
target recipe, so the standard `cmake`/`autotools`/`meson` classes those recipes already
inherit drive the build through `qcc` instead of Yocto's cross-gcc.

## Enabling it

Two lines in `conf/local.conf`:

```bitbake
# Build every target recipe with qcc (only affects MACHINE = qnx-aarch64le).
INHERIT += "qnx-toolchain"

# ptest pulls a Linux runtime closure (bash, gdbm, ...) that is not QNX-portable.
DISTRO_FEATURES:remove = "ptest"
```

It is **opt-in** on purpose: it changes how *every* target recipe builds. It is also inert
on any other `MACHINE`, and it never touches recipes that inherit `qnx-sdp` (our own), nor
native/nativesdk/cross recipes — those keep the host toolchain, or `cmake-native` would try
to build itself with `qcc`.

## Try it

```bash
bitbake bzip2                     # stock oe-core recipe, autotools
bitbake json-c                    # stock oe-core recipe, cmake
```

These build `libbz2.so.1.0.8` and `libjson-c.so.5.3.0` — QNX aarch64 shared objects — along
with their headers and static libraries, and stage them into the sysroot. A QNX image or
application recipe then consumes either with a plain `DEPENDS` and `-lbz2`/`-ljson-c`,
exactly as for a recipe you wrote yourself.

One from each build system is deliberate. Autotools asks the compiler what it is; CMake is
*told*, so it is the one that catches a wrong target — and it fails silently, by building
successfully for the wrong machine. See the CMake row in the table below.

## Putting it in an image

Building it is only half the job. The other half is that a stock recipe writes the same
image drop-in one of our own recipes writes, so an image installs it by name:

```bitbake
QNX_IFS_INSTALL = "bzip2"
```

There is a worked example — `recipes-image/qnx-ifs-reuse/`, an image whose entire payload
is unmodified oe-core:

```bash
bitbake qnx-ifs-reuse
bitbake -c dumpifs qnx-ifs-reuse | grep bz2
```

```
usr/bin/bunzip2 -> bzip2
usr/bin/bzip2
usr/bin/bzip2recover
usr/lib/libbz2.so.1
```

Nothing in that image's `.build` template mentions bzip2. Two things make it work, and
both are worth knowing about because they are what a Linux build does differently:

| | Linux | here |
| --- | --- | --- |
| Where runtime files go | `do_package` → `.ipk` → `do_rootfs` | straight out of the **sysroot** into `mkifs` |
| What the sysroot carries | build inputs only (`includedir`, `libdir`) | those **plus** `bindir`, `sbindir`, `libexecdir`, `sysconfdir` |

`qnx-toolchain` adds those extra directories to `SYSROOT_DIRS`, because with packaging
switched off the sysroot is the only endpoint there is. Without it `bitbake bzip2`
succeeds, `libbz2.so` appears, and `/usr/bin/bzip2` exists nowhere an image can see it.

The second half is the drop-in. After `do_install`, the recipe writes
`ifs.d/bzip2.files` describing what it installed — the same fragment format used by
recipes that inherit `qnx-sdp`, so the image class does not care which kind it is reading.
The one difference is how an entry names its source:

```
### bzip2
/usr/bin/bzip2=@QNX_IFS_SYSROOT@/usr/bin/bzip2
[type=link] /usr/bin/bzcat=bzip2
```

Our own recipes install into the stage tree, whose layout is what `mkifs -r` expects, so
they name their source by bare name and let `mkifs` find it. A stock recipe installs to
`/usr/bin` and `/usr/lib`, which are on no `mkifs` search path, so it names an absolute
path instead. It cannot write that path itself — the path belongs to whichever *image*
installs it — so it writes `@QNX_IFS_SYSROOT@` and the image expands it.

Everything else is shared: `QNX_IFS_ATTR`, `QNX_IFS_DEST`, `QNX_IFS_STARTUP_CMD` and the
startup ordering all work on a stock recipe exactly as on one you wrote. Set them from
`local.conf` or a `.bbappend`:

```bitbake
# make a stock daemon start at boot, after the drivers it needs
QNX_IFS_STARTUP_CMD:pn-mydaemon = "mydaemon &"
QNX_IFS_STARTUP_AFTER:pn-mydaemon = "my-driver"
```

## What it does, and why each piece is needed

The compiler was never the hard part — `qcc` is a self-contained sysroot, so a recipe
compiling `#include <stdio.h>` finds QNX's libc through `qcc` itself, with no OE glibc built.
The friction is that the GNU build *ecosystem* assumes Linux/gcc. The things below had to
be handled, and all of them are generic — they apply to every recipe of their kind, not
just to bzip2 and json-c:

| Problem | Cause | Fix |
| --- | --- | --- |
| Pulls `bash`/`gdbm`/`acl` and fails | `ptest` RDEPENDS a Linux runtime closure | `DISTRO_FEATURES:remove = "ptest"` |
| `configure`: "C compiler cannot create executables" | OE's base `CFLAGS` carry `-pipe` and debug flags `qcc`'s `cc1` rejects | class resets `CFLAGS` to `-O2` |
| Link fails: "cannot find libfoo.so" | libtool greps `$LD --help` for GNU-ld; OE set `LD=qcc`, whose `--help` is not GNU-ld-shaped, so it never builds the `.so` | class sets `LD` to the **raw** GNU ld (`aarch64-unknown-nto-qnx8.0.0-ld`); `qcc` still does the actual link via `$CC` |
| QA rejects the QNX ELF | Yocto's package QA expects Linux binaries | class `noexec`s `do_package*` — a QNX image is an IFS/QNX6 filesystem, never an `.ipk`, so the sysroot is the real endpoint |
| Builds, but nothing reaches the image | with packaging off, the sysroot is the endpoint, and oe-core does not stage `bindir`/`sbindir` for a target recipe | class adds them to `SYSROOT_DIRS` and writes an `ifs.d` drop-in (see above) |
| CMake recipe builds **x86-64**, or compiles Linux code paths | `cmake.bbclass` derives `CMAKE_SYSTEM_NAME` from `HOST_OS` (`linux` here), and `oecmake_map_compiler()` keeps only `argv[0]` of `CC`, dropping `-V<variant>` — bare `qcc` targets x86-64 | class appends `CMAKE_SYSTEM_NAME QNX` and `CMAKE_C_COMPILER_TARGET` to the generated toolchain file |

### The CMake case, specifically

The last row is worth expanding, because unlike the others it does not announce itself —
there is no error message. A CMake recipe under `qnx-toolchain` would build cleanly and
produce the wrong binary, twice over: for the wrong OS, because `CMAKE_SYSTEM_NAME` said
`Linux` and the project compiled its `epoll`/`/proc` branches; and for the wrong CPU,
because `CC` is `qcc -Vgcc_ntoaarch64le` but `oecmake_map_compiler()` passes only `qcc` to
CMake, and `qcc` with no `-V` targets **x86-64**:

```
$ qcc t.c -o t && file t
t: ELF 64-bit LSB pie executable, x86-64, ..., interpreter /usr/lib/ldqnx-64.so.2
```

`CMAKE_SYSTEM_NAME` has no variable to override — it is written inline by
`cmake_do_generate_toolchain_file`, a *shell* function — so the class appends a few
corrective `set()` lines to the generated `toolchain.cmake`. Later `set()` wins. This is a
supported pattern, not a hack: oe-core's own `cmake-qemu.bbclass` appends to the same file
the same way.

It stays short because CMake already knows QNX. `Modules/Platform/QNX.cmake` and
`Modules/Compiler/QCC*.cmake` ship with CMake, so `CMAKE_C_COMPILER_TARGET` becomes
`-V<variant>` on its own, and `CMAKE_SYSROOT` is emitted as `-Wc,-isysroot,` rather than
the `--sysroot` that would displace `qcc`'s built-in one.

Verify it on any CMake recipe:

```bash
bitbake json-c && readelf -hn tmp/work/*/json-c/*/image/usr/lib/libjson-c.so.5.3.0
```

`Machine: AArch64`, and a `.note` section owned by `QNX`.

## What you can actually build

Buildability is **per-recipe, not per-layer** — a layer is just a folder of recipes, and
each one is gated by whether its *code* and its *dependency closure* are QNX-portable.

- **Tier 1 — builds with little or no work.** Portable C/C++ libraries with small
  dependency closures: the bulk of oe-core and `meta-oe`'s libraries. `zlib`, `bzip2`
  (autotools) and `json-c` (cmake) are proven; `xz`, `expat`, `libffi`, `pcre2`, `zstd`
  and their kind are the expected shape. This is the real payoff — cherry-pick a portable
  library and consume it.
- **Tier 2 — builds after porting.** Code reaching for Linux/glibc specifics (`epoll`,
  `inotify`, `/proc`, Linux socket options). The toolchain gets it compiling; you fix the
  non-portable code, as any hand port would.
- **Tier 3 — effectively no.** Recipes whose *closure* is not portable — anything pulling
  `glib-2.0`, `systemd`, `dbus`, or `perl`/`python`/`bash` at build time, and `meta-qt6`'s
  Qt itself. The dependency tree would have to be ported too.

So: add `meta-openembedded` and cherry-pick its portable libraries — that works and is a
large win. Do **not** expect to "add `meta-qt6` and build the layer"; you would build
individual recipes from it, and the flagship ones will not come for free.

> **Honest status.** The mechanism is generic — none of the fixes above are specific to the
> recipes that exposed them — but it has been proven on three libraries: zlib and bzip2
> through autotools, json-c through cmake. Each new recipe is still an empirical question:
> the toolchain wall is gone, so what remains is ordinary porting, one recipe at a time.

## Why this is not the default

Making `qcc` the default toolchain is a large behavioural change, and most of this project
is built from recipes that inherit `qnx-sdp` by hand (and add the staging/IFS contract on
top). `qnx-toolchain` is the bridge for pulling in *external* libraries, not a replacement
for the bespoke recipes. Leave it off unless you are reusing another layer's recipes.
