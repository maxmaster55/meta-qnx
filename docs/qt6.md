# Qt 6 on QNX from stock meta-qt6

There are two ways to get Qt 6 onto QNX in this tree, and they are not competitors so
much as different bets. This document is about the second one.

| | `qt6-qnx` (meta-qnx-guest) | stock `meta-qt6` + bbappends |
| --- | --- | --- |
| Qt version | 6.8.3, pinned by the recipe | whatever the meta-qt6 branch is (6.10.3 here) |
| What builds it | one recipe driving Qt's own super-repo `cmake` build | one meta-qt6 recipe per Qt module |
| Host tools | built by hand, phase 1 of `do_compile` | `qtbase-native`, wired up by `qt6-cmake.bbclass` |
| Rebuild granularity | all of Qt | per module |
| Upstream tracking | you bump `PV` and the sha256 | you pull meta-qt6 |

Neither is deprecated. `qt6-qnx` is self-contained and known-good; the meta-qt6 route is
newer here, and gets you per-module rebuilds and someone else maintaining the recipes.

## Enabling it

meta-qt6 needs `meta-oe` and `meta-python` present. Add all three to `bblayers.conf`,
keep the `qnx-toolchain` lines from
[reusing-layers.md](reusing-layers.md), and build:

```bash
bitbake qtbase
```

meta-qnx's Qt bbappends live in `dynamic-layers/qt6-layer/` and are wired through
`BBFILES_DYNAMIC`, so they appear only when meta-qt6 is in the build. meta-qnx keeps
`LAYERDEPENDS = "core"` and a build without meta-qt6 never parses them.

## Why a bbappend is enough

meta-qt6 has no QNX support — grep it for `qnx` or `nto` and you get nothing. It does not
need any, because almost everything that makes Qt a Linux build here is *configuration*:

| Blocker | Fixed by | Scope |
| --- | --- | --- |
| `CMAKE_SYSTEM_NAME Linux`, and `-V<variant>` dropped from `$CC` | `qnx-toolchain.bbclass` | **every CMake recipe** |
| `bits/wordsize.h: No such file` | `qnx-toolchain.bbclass` skips `oe_multilib_header` | **every recipe using it** |
| `libfoo.so, needed by libbar.so, not found (try -rpath-link)` | `qnx-toolchain.bbclass` adds `-rpath-link` to the CMake linker flags | **every two-level library dependency** |
| `PACKAGECONFIG_DEFAULT` pulls `dbus glib udev libinput xkbcommon fontconfig`, and `PACKAGECONFIG_GRAPHICS` appends `linuxfb` | one line in the bbappend replacing the list | Qt |
| `undefined reference to 'eventfd'` | `-leventfd`; QNX 8 has it in a standalone library, Linux has it in libc | Qt |
| `undefined reference to '__res_nmkquery'` | `-DFEATURE_libresolv=OFF`; QNX has no glibc resolver | Qt |
| `The OpenGL functionality tests failed!` | `no-opengl`; Qt requires an explicit decision once `gui` is on | Qt |
| `freetype` wants libpng | `recipes-ports/freetype_%.bbappend` | freetype |
| Delivery — `do_package` is `noexec` under `qnx-toolchain` | nothing. Qt installs under `${libdir}`/`${bindir}`, which the sysroot already stages. | — |

The top three are worth separating out: they are **not Qt fixes**. They were pre-existing defects in
`qnx-toolchain.bbclass` that no recipe in this layer was complex enough to expose. zlib, bzip2 and
json-c are all single libraries one level deep; Qt is the first workload with real depth. That is the
argument for doing this exercise even if you never ship meta-qt6's Qt.

Each of the three also failed *misleadingly*. The multilib one fails in a recipe far from the one that
installed the bad header. The other two report a wall of undefined references from inside a library
that is perfectly fine — it is merely missing a link input. Three separate failures pointed at the
wrong library.

The delivery row is the surprise. It looks like the hard one — meta-qt6 splits Qt into
`-plugins`, `-qmlplugins`, `-tools` with `FILES:`/`RDEPENDS:` doing real work — but
`qt6-paths.bbclass` puts all of it under `${libdir}` and `${bindir}`, and
`qnx-toolchain` stages those. Nothing had to be re-solved.

## What is verified

```bash
bitbake qtbase qtdeclarative
```

`qtbase` builds QtCore, QtGui, QtNetwork, QtSql, QtXml, QtConcurrent and QtTest, plus the
platform plugins — including **`libqqnx.so`**, Qt's QNX Screen backend, which links
`libscreen.so.1` from the SDP. Qt found Screen by itself; nothing here told it where to look.

`qtdeclarative` builds the whole QML/Quick stack: `Qt6Qml`, `Qt6Quick`, QuickControls2
(Basic, Fusion, Material, Imagine, Universal), QuickLayouts, QuickShapes, QuickEffects,
QuickDialogs, the Labs modules, and the `qml`/`qmlscene`/`qmltestrunner` tools.

Both write `ifs.d` drop-ins, so an image installs them by name.

The check that matters is not that it compiled but *which* Qt compiled:

```
$ readelf -d libQt6Core.so.6.10.3 | grep NEEDED
  libeventfd.so.1   libfsnotify.so.1   libslog2.so.1
  libc++.so.2       libc.so.6         libm.so.3
```

`libslog2` is QNX's system logger and `libfsnotify` its inotify equivalent. Qt built its
**QNX backends**. A Linux-configured build reaches glibc's `inotify`/`epoll` and links
none of those, so this single line distinguishes "it built" from "it built the right
thing" — which matters here because a wrong `CMAKE_SYSTEM_NAME` produces a clean,
successful, useless build.

## Known rough edges

**The drop-in is enormous.** `qtbase.files` is ~488 entries and includes Wayland protocol
XML, `README.md`, `REUSE.toml`, `qt_attribution.json` and `.prl` files. The harvester in
`qnx-image-contract.bbclass` takes everything staged that is not explicitly excluded,
which is right for bzip2 and wrong for Qt. Qt is simply the first recipe big enough to
show it. In a RAM-resident IFS that is real bloat; on a QNX6 data disk it is only untidy.

**Version skew.** meta-qt6's branch here is 6.10, against `qt6-qnx`'s 6.8.3. Anything
built against the staged Qt — `qt-cluster` — is picking a side.

**Nothing has run.** Every claim above is about what links, not what works. "`libqqnx.so`
links `libscreen`" is a long way from "a QML scene renders on the board". No Qt binary
produced this way has been put in an image or executed on hardware, and the QNX Screen
service has to be running and configured before one could be.

**OpenGL is off.** `no-opengl` means QtQuick falls back to its software rasteriser. That is
enough to render, and it is not what a cluster UI wants. Turning it on means Qt finding
QNX's GL implementation, which is untried here.

**Memory.** Qt links several large objects in parallel and will take a machine down if
`BB_NUMBER_THREADS` × `PARALLEL_MAKE` is set to the core count. `4` and `-j 4` are known to
survive; the defaults are not.
