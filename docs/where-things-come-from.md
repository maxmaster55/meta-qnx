# Where things come from

Something is missing from your image. Where do you get it?

QNX components arrive through **four different channels**, and picking the wrong one wastes
a lot of time — you cannot compile `procnto`, and you should not hand-write a recipe for
something QNX already publishes as a package. This is the map.

- [The four sources](#the-four-sources)
- [Which one do I need?](#which-one-do-i-need)
- [The three search roots](#the-three-search-roots)
- [The limitation nothing solves](#the-limitation-nothing-solves)
- [Worked example: D-Bus](#worked-example-d-bus)

---

## The four sources

| Source | What lives there | How you get it |
| --- | --- | --- |
| **QNX SDP** | QNX's own components: `procnto`, libc, `devb-*`/`devc-*`/`io-sock`, Screen, the hypervisor (`qvm`, `vdev-*.so`), toybox | `QNX_SDP_FEATURES` + lockfile → `-c resolve_sdp` / `-c install_sdp` |
| **repo.oss.qnx.com** | Prebuilt open source: dbus, glib, sqlite, openssl, Qt | `-c search_oss` → paste the stub → `inherit qnx-apk` |
| **BSP / project tree** | Board drivers and firmware the SDP does **not** ship | `QNX_IFS_EXTRA_ROOTS`, sourced from `QNX_PROJECT_SRC` |
| **Built from source** | Your applications, and portable upstream libraries | `qnx-cmake` / `qnx-meson` / `qnx-autotools` (+ `qnx-src`) |

The two genuinely **QNX-specific** rows are the first and third, and they differ in kind:

**The SDP is licensed and prebuilt.** Everything QNX — kernel, libc, drivers, shells,
Screen, the hypervisor — arrives as binaries from QNX's servers via
`qnxsoftwarecenter_clt`, authenticated with your myQNX credentials. Yocto does not and
*cannot* compile any of it: there is no QNX `TCLIBC`, no `TARGET_OS=nto`, no `procnto`
recipe. bitbake is orchestrating an SDP that already exists. Full guide in [sdp.md](sdp.md).

**The BSP tree is the gap the SDP leaves.** A given board needs drivers no SDP carries. In
`meta-qnx-hyp` those are the Raspberry Pi 5 parts — `wdtkick`, `i2c-dwc-rpi5`,
`devc-serpl011-rpi5`, `gpio-rp1`, `msix-rp1` — plus the Pi firmware itself (`start4.elf`,
`fixup4.dat`, `bcm2712-rpi-5-b.dtb`, `overlays/`), which are Broadcom artifacts and not QNX
ones at all. They come out of the hypervisor monorepo, which is why `qnx-host-image` and
`qnx-host-disk` `SkipRecipe` when `QNX_PROJECT_SRC` is unset rather than failing obscurely.

The other two rows are not QNX-specific at all, and that is the point: `repo.oss.qnx.com`
is ordinary open source that QNX happened to build, and rows 4 covers anything whose source
you have.

## Which one do I need?

The signal that something is missing is almost always `mkifs`:

```
Host file 'foo' not available
```

Then, in order of how cheap the answer is:

1. **A standard QNX component?** → `bitbake -c search qnx-sdp`, add the feature to
   `QNX_SDP_FEATURES`, then `-c resolve_sdp` → `-c install_sdp` → `-c write_lockfile`.
2. **A known open-source name?** →
   `bitbake -c search_oss qnx-sdp -R oss-search.conf`, with `QNX_OSS_SEARCH = "foo"` in
   that file. If it is there, the
   task prints the recipe.
3. **Board-specific?** → it is in your BSP tree; add that tree via `QNX_IFS_EXTRA_ROOTS`.
   If it is not there either, it does not exist and you are porting it.
4. **Yours, or portable upstream source?** → a recipe with one of the three build-system
   driver classes. See the [cookbook](cookbook.md).

Two special cases worth knowing before you go hunting:

- **`ls`, `cat`, `cp`, `uname`, `grep`** are not missing — QNX 8 ships no standalone
  versions. They are `toybox`, a multicall binary, and images get it plus a link per
  command automatically. See `QNX_IFS_TOYBOX_CMDS`.
- **A nested module** (`lib/dll/pci/...`) is usually found but unreferenceable: the mkifs
  search path is flat, so `lib/dll` is searched and `lib/dll/pci` is not. Name it by
  subpath — `/lib/dll/pci/pci_slog2.so=pci/pci_slog2.so`.

## The three search roots

At `mkifs` time the four sources collapse into three roots, passed as repeated `-r` and
searched **left to right**, before `$QNX_TARGET`:

| Order | Root | Holds |
| --- | --- | --- |
| 1 | `QNX_IFS_ROOT` — the recipe sysroot | everything Yocto built (rows 2 and 4) |
| 2 | `QNX_IFS_EXTRA_ROOTS` — the BSP tree | board drivers the SDP lacks (row 3) |
| 3 | `$QNX_TARGET` — the SDP | everything standard (row 1) |

Leftmost wins, which is what lets a layer override an SDP binary with its own build without
touching the SDP — remember it is used strictly read-only.

A root that does not exist is a hard error rather than a silent "not available" later.

## The limitation nothing solves

**You cannot ask "which package provides this file."** p2 metadata (what the Software
Center exposes) carries no file lists, and `search_oss` matches package names, descriptions
and licences — not archive contents. Both searches get you to the right *namespace*; the
last step is human.

This is the real friction in step 1 above, and it is worth knowing rather than
rediscovering. When a search comes up empty, the answer is usually one of:

- it is `toybox` (see above),
- it is in a namespace whose name does not contain the word you searched for — try
  `bitbake -c search qnx-sdp` unfiltered and read the ~550 lines once,
- it is genuinely not in the SDP, and you are looking at row 3 or row 4.

## Worked example: D-Bus

D-Bus is a good case because the obvious guess is wrong. It is **not** in the SDP — it is
row 2, ordinary open source that QNX packages:

```bash
echo 'QNX_OSS_SEARCH = "dbus"' > oss-search.conf
bitbake -c search_oss qnx-sdp -R oss-search.conf
```

```
PACKAGE                      VERSION               SIZE  CHANNEL          DESCRIPTION
dbus                         1.16.2-r2             0.4M  8.0.3/extra      Freedesktop.org message bus system
dbus-dev                     1.16.2-r2             0.0M  8.0.3/extra      Freedesktop.org message bus system (development files)
dbus-glib                    0.114-r0              0.1M  8.0.3/extra      GLib bindings for DBUS
python3-dbus                 1.4.0-r0              0.1M  8.0.3/extra      Python3 bindings for DBUS
```

Three things this tells you that a web search does not:

1. **The channel is `8.0.3/extra`**, not the `8.0.4/qnx-extra` default — so the recipe
   needs `QNX_OSS_CHANNEL`. That channel is also much the larger of the four (~2000
   packages against ~100), and is where most familiar libraries live.
2. **The `-dev` split is Alpine-style.** The runtime package has the binaries and shared
   libraries; headers are a separate `-dev` package you only need if something compiles
   against it.
3. **Its dependencies are `glib qnx-io-sock`.** `qnx-io-sock` you already have from the
   SDP; **`glib` needs its own `qnx-apk` recipe** (same channel, 2.3 MB). So this is two
   recipes, not one — which the index tells you up front instead of at link time.

Paste the printed stub, run `bitbake -c fetch dbus` once for the checksum, and add `dbus`
to `QNX_IFS_INSTALL`.

> **Not verified on hardware.** These packages are built for the 8.0.3 channel; whether
> they run correctly under an 8.0.4 SDP is not something the index states, and nothing in
> this layer has been run on a board yet. Check before relying on it.

---

- [sdp.md](sdp.md) — managing the SDP, and both search tasks in full
- [cookbook.md](cookbook.md) — the recipe patterns for row 4
- [reusing-layers.md](reusing-layers.md) — building stock oe-core recipes for QNX
