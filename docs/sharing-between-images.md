# Sharing between images

A hypervisor host and its guests are different images, but they are not *very* different
images. They boot the same way, carry the same shell and utilities, mount disks with the
same block stack, and run several of the same applications. Left alone, that similarity
becomes two copies of the same 200-line build file and two copies of the same install
list, and the day one of them gains a component the other quietly does not.

There are two mechanisms for this, because there are two kinds of duplication.

| Duplicated thing | Mechanism |
| --- | --- |
| A list of *recipes* both images install | **packagegroups** — `qnx-packagegroup.bbclass` |
| A block of *build-file text* both templates contain | **template includes** — `#include` |

---

## Packagegroups: one name for a set of recipes

A packagegroup is an ordinary recipe that builds nothing and exists to be a name:

```bitbake
SUMMARY = "SOME/IP runtime libraries"
LICENSE = "CLOSED"

inherit qnx-packagegroup

QNX_PACKAGEGROUP_INSTALL = "vsomeip commonapi-core commonapi-someip boost"
```

An image installs it exactly like an application:

```bitbake
QNX_IFS_INSTALL = "packagegroup-qnx-someip my-app"
```

Groups nest — a group may list other groups — and `qnx-ifs.bbclass` expands the whole
tree when it generates the build file. Order is preserved, and a name reached twice is
installed once.

Two exist today, and both are named after what they *are* rather than which image uses
them, which is the point:

| Group | Members | Installed by |
| --- | --- | --- |
| `packagegroup-qnx-hyp-common` | `frame-router`, `rpi-gpio` | the host image **and** the guest image |
| `packagegroup-qnx-someip` | `vsomeip`, `commonapi-core`, `commonapi-someip`, `boost` | the guest image |

`packagegroup-qnx-hyp-common` is the one that pays for itself: before it existed, both
image recipes named `frame-router` and `rpi-gpio` individually, in two files in two
layers, and adding a third shared component meant remembering both.

### Why the membership is a file, not just DEPENDS

`DEPENDS` alone looks like it should be enough, and it is not — but only for one specific
reason worth stating, because it is the sort of thing that gets "simplified" back out.

`DEPENDS` *does* get every member's files into the image's `RECIPE_SYSROOT`; OE stages the
full recursive closure, not just direct dependencies. What it does not do is tell the
image which **names** to read drop-ins for. `qnx-ifs.bbclass` walks `QNX_IFS_INSTALL`
deliberately, rather than globbing the drop-in directory, so an image contains exactly
what it asked for and not whatever else happens to be in the shared sysroot. So a group
also writes its membership to `ifs.d/<name>.install`, and the image reads that to extend
its list.

---

## Template includes: one copy of the shared build-file text

An image's `.build` template may pull in a fragment by name:

```
#include qnx-boot.build.inc
```

Fragments are resolved against the including file's own directory first, then
`QNX_TEMPLATE_INCLUDE_PATH`. Each layer appends its own directory in `conf/layer.conf`:

```bitbake
QNX_TEMPLATE_INCLUDE_PATH += "${LAYERDIR}/files/ifs"
```

so a fragment in `meta-qnx` is available to an image in `meta-qnx-hyp` without either
knowing where the other lives. Includes nest, cycles are an error, and editing a fragment
rebuilds the images that use it.

The `#` is not decoration: `mkifs` treats the line as a comment, so a template with
includes in it is still a valid build file on its own.

### The fragments meta-qnx ships

| Fragment | What it is | Used by |
| --- | --- | --- |
| `qnx-boot.build.inc` | image attributes and the `boot = { … }` block | every image |
| `qnx-startup-preamble.build.inc` | `procmgr_symlink`, `pipe`, `slogger2`, `dumper`, `mqueue`, `random` | every image |
| `qnx-base.build.inc` | `/bin/sh`, `/tmp`, `/dev/console` links; `ksh`, `pidin`, `waitfor`, `slay`, `mount` | every image |
| `qnx-block.build.inc` | `libcam`, `io-blk`, `cam-disk`, `fs-qnx6` | any image that mounts a disk |
| `qnx-net.build.inc` | `io-sock`, `ifconfig`, `route`, `dhcpcd` | any image with an interface |

Note what is deliberately **not** in `qnx-block` and `qnx-net`: the drivers. That is
exactly what differs — a guest uses `devb-virtio` and `devs-vtnet_mmio.so` against vdevs
its host provides; the host uses `devb-ram` and real NIC drivers plus
`mods-vdevpeer-net.so` to serve its guests. Each image lists the driver it has hardware
for and includes the fragment for the rest.

Where the two images differ in a small way rather than a structural one, that becomes a
variable instead of a second fragment. `/dev/console` is the example: the guest's console
is a virtio console, the host's is the board's UART, so `qnx-base.build.inc` writes
`@QNX_CONSOLE_DEV@` and the host image sets `QNX_CONSOLE_DEV = "/dev/ser10"`.

---

## Two things that will bite you

Both come from the same root: expansion and inclusion are **textual**, and neither knows
what a comment is.

**Never name a marker inside a comment.** A template comment that mentions the
applications marker gets that marker substituted, which drops a few hundred file records
into the middle of your sentence. `mkifs` then reports `Improper filename specification`
on a line you thought was prose.

**Never put a brace in a fragment included inside a script block.** `mkifs` does not strip
comments inside `[+script] … = { … }`, so a `}` in a comment ends the script early and
every line after it is read as a file record. The classic symptom is
`Host file 'nto' not available` — `SYSNAME=nto` having become a record.
