# Adding a recipe

End to end: from "I have some software" to "it is on the board and it started".

[cookbook.md](cookbook.md) has the recipe text for each build system — makefile,
CMake, meson, autotools, plain files. This is the surrounding workflow, which is
where the time actually goes: deciding what kind of thing you are adding, getting
its output into the right place, and getting it into an image.

## Contents

- [First: which kind of thing is it?](#first-which-kind-of-thing-is-it)
- [1. Write the recipe](#1-write-the-recipe)
- [2. Install into the stage tree](#2-install-into-the-stage-tree)
- [3. Add it to an image](#3-add-it-to-an-image)
- [4. Place files mkifs cannot find](#4-place-files-mkifs-cannot-find)
- [5. Start it at boot](#5-start-it-at-boot)
- [Checklist](#checklist)
- [Errors you will hit](#errors-you-will-hit)

## First: which kind of thing is it?

Three different answers, and picking the wrong one is the most expensive mistake
here because it is the one you notice last.

| It is | Use | Example |
| --- | --- | --- |
| Software you build from source | An application recipe — `qnx-sdp` plus a build-system class | `motor-controller`, `rpi-gpio` |
| Files already in the SDP | An **SDP component** — `qnx-sdp-component` | `qnx-screen`, `qnx-pci` |
| A set of the above, named once | A **packagegroup** — `qnx-packagegroup` | `packagegroup-qnx-someip` |

An SDP component installs *nothing*. The SDP is already on disk and mkifs
searches it, so copying files through the stage tree would add a hop and no
capability. What a component produces is a list: these thirty-three files are one
thing, take them or none of them.

That matters more than it sounds. `pci-server` is one binary, ~30 dlopen'd
modules and two config files; take three of the thirty and you get a server that
starts, finds no way to enumerate a bus, and exits — after which every driver
behind it fails in a way that mentions anything but PCI.

```bitbake
SUMMARY = "PCI server and its modules"
LICENSE = "CLOSED"
inherit qnx-sdp-component
QNX_COMPONENT_FILES = "pci-server pci-connector libpci.so pci/pci_server-namespace.so ..."
```

Destinations are derived from where each file was found: something under
`<root>/${QNX_PROCESSOR}/usr/lib` lands at `/usr/lib`. Override individually with
`QNX_COMPONENT_DEST[name]`, and mark genuinely optional files in
`QNX_COMPONENT_OPTIONAL` so an SDP without them still parses.

## 1. Write the recipe

For an application, the shape is always:

```bitbake
SUMMARY = "..."
LICENSE = "CLOSED"

inherit qnx-sdp qnx-src        # + qnx-cmake / qnx-meson / qnx-autotools

QNX_SRC_REPO = "git://git@github.com/org/thing.git;protocol=ssh;branch=main"
```

`qnx-src` gives you the fetch. Two things about it worth knowing up front:

- `QNX_SRC_REV` defaults to `${AUTOREV}`, which needs the network at **parse**
  time — every `bitbake` invocation, not just a fetch. Pin it to a commit for
  reproducible and offline builds.
- `QNX_SRC_LOCAL` points at a checkout and switches the recipe to building that
  working tree in place, which is what you want while developing.
- `QNX_SRC_SUBDIR` for a repository holding several applications.

If the repository needs a header from another recipe, `DEPENDS` on it and pass
the path — do not reach for a sibling directory:

```bitbake
DEPENDS = "rpi-gpio"
CFLAGS:append = " -I${RECIPE_SYSROOT}${QNX_STAGE_INCLUDEDIR}"
```

Relative `-I../other-project/include` works only while everything lives in one
source tree, and breaks the moment the repository is split out. `motor-controller`
and `motor-data-producer` both do it the way above.

See [cookbook.md](cookbook.md) for the per-build-system details.

## 2. Install into the stage tree

This is the contract. Install under `${QNX_STAGE_DIR}`, in the layout the target
expects:

```
${QNX_STAGE_DIR}/${QNX_PROCESSOR}/usr/bin/thing   -> /usr/bin/thing in an image
${QNX_STAGE_DIR}/${QNX_PROCESSOR}/sbin/thing      -> /sbin/thing
${QNX_STAGE_DIR}/usr/include/sys/thing.h          -> sysroot only, never an image
```

Anything under `${QNX_PROCESSOR}/` is a candidate for an image; anything outside
it is build-time only. A CMake project whose own `install()` rules already follow
the QNX convention needs no `do_install` at all — see `rpi-gpio`.

Then the automatic pass picks up what you installed and writes the mkifs records.
Two varflags adjust individual entries:

```bitbake
QNX_IFS_DEST[rpi_gpio] = "/sbin/rpi-gpio"          # different path
QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"  # setuid, runs as root
```

## 3. Add it to an image

One word:

```bitbake
QNX_IFS_INSTALL += "your-recipe"
```

in `qnx-host-image_1.0.bb` or `qnx-guest-image_1.0.bb`. That adds the `DEPENDS`
and merges the recipe's drop-in when the build file is generated.

For something large — a Qt deploy tree, a graphics stack — use the guest's
**rootfs** instead:

```bitbake
QNX_ROOTFS_INSTALL += "your-recipe"
```

An IFS is copied into RAM whole at boot, so anything of size belongs on the QNX6
data partition. `qt-cluster` is ~126 MB and `qnx-screen-virtio` ~279 MB; both are
rootfs, and the guest union-mounts the disk at `/` early enough that the paths
come out the same.

If two images both need it, put it in a packagegroup rather than in both image
recipes — see [sharing-between-images.md](sharing-between-images.md).

## 4. Place files mkifs cannot find

mkifs searches `lib`, `lib/dll`, `usr/lib`, `bin`, `sbin`, `usr/bin`,
`usr/sbin`, `usr/libexec`, `boot/sys` under each root, **by bare name**. It does
not descend into arbitrary nested directories and it will not find anything
destined for `/etc`, `/scripts`, `/usr/share` or a nested driver directory.

For those, turn the automatic pass off and name each file:

```bitbake
QNX_IFS_AUTO_ENTRIES = "0"

QNX_IFS_EXTRA_ENTRIES = "\
/usr/share/screen/graphics-virtio-mmio.conf=@QNX_IFS_ROOT@/guest-conf/graphics-virtio-mmio.conf\n\
[perms=0755] /scripts/graphics-virtio-start.sh=@QNX_IFS_ROOT@/guest-conf/graphics-virtio-start.sh\
"
```

`@QNX_IFS_ROOT@` — at-signs, not `${...}` — is deliberate. It is expanded by the
*image* recipe when the fragment is merged, because the path depends on which
image installs this and is unknowable in the recipe. A `${QNX_IFS_ROOT}` would
expand to nothing at parse time.

Leaving `QNX_IFS_AUTO_ENTRIES` on for such a recipe is not fatal, just noisy: the
automatic pass warns about every file it cannot place.

## 5. Start it at boot

Three variables, from `qnx-image-contract`:

```bitbake
QNX_IFS_STARTUP_CMD = "your-thing &"
QNX_IFS_STARTUP_AFTER = "qnx-io-sock"
QNX_IFS_STARTUP_WAITFOR = "/dev/your-thing"
```

`AFTER` orders the command. `WAITFOR` is what makes the ordering mean anything —
a resource manager that backgrounds itself returns long before it has registered
its device, so without the `waitfor` the next command runs against a device that
does not exist yet. Both, or neither.

Not everything should start at boot. A driver that faults while attaching takes
its manager down with it — `io-sock` going down takes the wired NIC, the bridge
and any ssh session on them. During bring-up, ship the script and run it by hand.

## Checklist

- [ ] `LICENSE` set (`CLOSED` for anything proprietary)
- [ ] `QNX_SRC_REV` pinned, or `AUTOREV` accepted knowingly
- [ ] Installs under `${QNX_STAGE_DIR}/${QNX_PROCESSOR}/...`, headers outside it
- [ ] `DEPENDS` on anything whose headers or libraries it compiles against
- [ ] Added to `QNX_IFS_INSTALL` or `QNX_ROOTFS_INSTALL` — a recipe that builds and is in neither produces nothing
- [ ] `QNX_IFS_AUTO_ENTRIES = "0"` if it stages anything outside the search path
- [ ] If it has to run at boot, `QNX_IFS_STARTUP_WAITFOR` as well as `_CMD`

Then check what you actually got, without hardware:

```bash
bitbake -c dumpifs   qnx-host-image    # is the file in the image?
bitbake -c dumpbuild qnx-host-image    # ...and if not, was it ever asked for?
```

Run them in that order. A file missing from `dumpifs` but present in `dumpbuild` is
an mkifs search-path problem; missing from both means the recipe never contributed
it, and `QNX_IFS_INSTALL` or `QNX_IFS_EXTRA_ENTRIES` is where to look.

## Errors you will hit

**`Entry 'usr/sbin/sshd' redefined`** — two recipes claim one path. mkifs treats
this as an error, not a warning, so an entry belongs in exactly one place. Usually
it means a component now provides something an image's build file still lists by
hand. Delete the one in the build file.

Note the near-miss version: the same binary at `/bin/screen` and `/sbin/screen`
is **not** a redefinition, so mkifs says nothing and the image simply carries it
twice, with PATH order deciding which runs.

**`'thing' is in QNX_IFS_INSTALL but contributes nothing to the image`** — the
recipe built and installed nothing under `${QNX_PROCESSOR}/`, or installed only
headers. Check `do_install`.

**`Warning: Host file 'x.so' missing`** — a name in a build file that is not on
any search root. The image still builds; the file is simply absent, and whatever
needed it fails on the board. Worth treating as an error during bring-up.

**`not found under <roots>: ...`** at parse time — an SDP component naming a file
this SDP does not have. Either the SDP lacks the package (see `QNX_SDP_FEATURES`
in [sdp.md](sdp.md)) or the name is wrong. Genuinely optional files go in
`QNX_COMPONENT_OPTIONAL`.

**Something is missing at runtime that nothing lists** — the dependency closure
reads `DT_NEEDED`, so it cannot see a library opened with `dlopen` by literal
name. `libepoxy` asking for `libGLESv2.so.2` is the standing example; the fix was
an explicit `[type=link]` entry. If a program dies looking for a library the
build never mentioned, this is why.

## See also

- [cookbook.md](cookbook.md) — recipe text per build system
- [configuration.md](configuration.md) — settings, and which must agree
- [where-things-come-from.md](where-things-come-from.md) — the four sources and three search roots
- [sharing-between-images.md](sharing-between-images.md) — packagegroups and template includes
- [variables.md](variables.md) — full variable reference
