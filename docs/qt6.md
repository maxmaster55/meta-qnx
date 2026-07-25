# Qt 6 on QNX from stock meta-qt6

Qt 6 comes from **stock meta-qt6**, cross-compiled for QNX by `qnx-toolchain.bbclass`
plus the bbappends in `dynamic-layers/qt6-layer/`. There is no QNX-specific Qt recipe in
this tree.

There used to be one — `qt6-qnx` in meta-qnx-guest, which drove Qt's own super-repo
`cmake` build at 6.8.3 and staged a whole SDK under `${QNX_STAGE_DIR}/qt`. It was
removed in favour of this route:

| | removed `qt6-qnx` | stock `meta-qt6` + bbappends |
| --- | --- | --- |
| Qt version | 6.8.3, pinned by the recipe | whatever the meta-qt6 branch is (6.10.3 here) |
| What builds it | one recipe driving Qt's super-repo `cmake` build | one meta-qt6 recipe per Qt module |
| Host tools | built by hand, phase 1 of `do_compile` | `qtbase-native`, wired by `qt6-cmake.bbclass` |
| Rebuild granularity | all of Qt | per module |
| Upstream tracking | bump `PV` and the sha256 | pull meta-qt6 |

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

**Layout differs from the old recipe, and silently.** `qt6-qnx` installed Qt under its
own prefix, so `<prefix>/lib`, `<prefix>/qml`, `<prefix>/plugins`. meta-qt6's
`qt6-paths.bbclass` puts QML at `${libdir}/qml` and plugins at `${libdir}/plugins`.
`qt_cluster`'s CMakeLists derives its deploy paths as `${Qt6_DIR}/../../..` plus `/qml`
and `/plugins`, which is right for the former and wrong for the latter — and it does not
fail the configure. It deploys an empty `qml/` and the app cannot start. Those are
`CACHE PATH` variables, so `qt-cluster` overrides `QT6_QML_DIR`/`QT6_PLUGIN_DIR`
explicitly and asserts a non-empty `deploy/qml` in `do_install`.

**Nothing has run.** Every claim above is about what links, not what works. "`libqqnx.so`
links `libscreen`" is a long way from "a QML scene renders on the board". No Qt binary
produced this way has been put in an image or executed on hardware, and the QNX Screen
service has to be running and configured before one could be.

**OpenGL is off.** `no-opengl` means QtQuick falls back to its software rasteriser. That is
enough to render, and it is not what a cluster UI wants. The old `qt6-qnx` recipe had the
same limitation (`-DINPUT_opengl=no`), so this is not a regression — but it is not fixed
either.

The pieces to fix it do exist as prebuilt packages, in the **default** OSS channel:

```bash
bitbake -c search_oss qnx-sdp -R oss-search.conf   # QNX_OSS_SEARCH = "qnx-gles"
```

| Package | Channel |
| --- | --- |
| `qnx-egl`, `egl-headers` | `8.0.4/qnx-extra` |
| `qnx-gles`, `gles-headers` | `8.0.4/qnx-extra` |
| `qnx-libdrm`, `qnx-libgbm` | `8.0.4/qnx-extra` |
| `qnx-vulkan`, `vulkan-headers` | `8.0.4/qnx-extra` |

The SDP also already ships `libEGL.so.1`/`libGLESv2.so.1` (the host image installs them).
So the blocker is not availability but Qt's configure tests finding a GL it accepts —
staging the `-headers` packages into the sysroot and dropping `no-opengl` from
`QNX_QTBASE_PACKAGECONFIG` is the experiment. Untried.

**Memory.** Qt links several large objects in parallel and will take a machine down if
`BB_NUMBER_THREADS` × `PARALLEL_MAKE` is set to the core count. `4` and `-j 4` are known to
survive; the defaults are not.
