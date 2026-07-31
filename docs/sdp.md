# Managing the SDP

The SDP is not built by Yocto — it is installed by QNX's own
`qnxsoftwarecenter_clt` from QNX's servers. What this layer adds is a way to say
*what* should be in it, check that it is, and make it so.

> The SDP is only one of the four places QNX components come from. If you are not
> sure whether what you need is even in it, start at
> [where-things-come-from.md](where-things-come-from.md).

## Intent vs. resolved

The split follows `package.json` / `package-lock.json`:

| | What it is | Who writes it |
| --- | --- | --- |
| `QNX_SDP_FEATURES` | intent — readable, unpinned | you |
| the **lockfile** | the resolved result: exact ids and versions | `bitbake -c write_lockfile` |

**Normally you never hand-write a version.** p2 (the provisioning engine
`qnxsoftwarecenter_clt` wraps) resolves dependencies, `-verifyOnly` proves a
combination is satisfiable before anything is touched, and the snapshot records
what it actually chose. Two machines with the same lockfile get the same SDP, and
regenerating it is a reviewable diff.

The exceptions are real, though, and have their own section — installing a
package the lockfile has never seen, and holding one back because the newest does
not fit the rest. See [Choosing versions](#choosing-versions).

If you already have a QNX package list, you probably already have a lockfile: the
format is exactly what `qnxsoftwarecenter_clt -listInstalledRoots` prints, so an
existing `qsc_install_packages.list` can be adopted unchanged.

## Configuration

Where the SDP lives is `QNX_SDP_ROOT`, which defaults to `${TOPDIR}/qnx-sdp` in the same
spirit as `DL_DIR` — so with no configuration at all, `install_sdp` creates one inside the
build directory. Point it elsewhere to manage an SDP you already have.

```bitbake
QNX_SDP_ROOT = "/path/to/qnx800"          # optional; defaults into the build dir
QNX_QSC_CLT = "/path/to/qnxsoftwarecenter/qnxsoftwarecenter_clt"
QNX_SDP_LOCKFILE = "${QNX_PROJECT_SRC}/qsc_install_packages.list"
QNX_SDP_FEATURES = "core toolchain utils networking hypervisor"
```

Credentials are **never** in a layer or a recipe. Point at a file outside version
control, in the same `@file` form the SDP's own tooling uses:

```
-myqnx.user
you@example.com
-myqnx.password
secret
```

```bitbake
QNX_SDP_CREDENTIALS_FILE = "${HOME}/.qnx/qsc-credentials"   # the default
```

`chmod 600` it. The path is excluded from task signatures and never echoed.

## Features are patterns, not lists

An SDP has hundreds of packages — qnx800 alone has ~550 — so a feature is a set
of **namespace glob patterns** matched against the lockfile, not an enumeration:

```bitbake
QNX_SDP_FEATURE[networking] = "target.net.*"
QNX_SDP_FEATURE[utils]      = "osr.toybox target.utils.*"
```

Patterns are relative to `${QNX_SDP_PKG_PREFIX}` (derived from
`QNX_SDP_VERSION`, so nothing hardcodes 8.0) unless they already start with
`com.qnx.`. This survives QNX reorganising a namespace's contents, and it is why
a feature is two patterns rather than forty ids.

Shipped features are in [`conf/qnx-sdp-features.inc`](../conf/qnx-sdp-features.inc):
`core`, `toolchain`, `utils`, `networking`, `filesystems`, `storage`, `pci`,
`usb`, `security`, `connectivity`, `screen`, `multimedia`, `audio`, `hypervisor`,
`hypervisor-guest-arm`, `hypervisor-guest-x86`, `debug`, `python`, `bsp-hw`.

A project adds its own without editing the layer:

```bitbake
QNX_SDP_FEATURE[my-thing] = "target.mm.* com.qnx.qnx800.osr.something"
QNX_SDP_FEATURES += "my-thing"
```

A feature that matches nothing at all warns. Individual patterns that match
nothing do not — with globs it is normal for a feature to span namespaces an SDP
does not carry (`host.win.*` on a Linux install).

### Features can only select what the lockfile already has

The one surprising thing about features, and a warning that is easy to misread:

```
WARNING: QNX_SDP_FEATURE[bsp-rpi5] matched no package in the lockfile.
```

Patterns are matched **against the lockfile** — that is what keeps versions
pinned — so a feature is a filter over packages the snapshot already records. It
cannot pull in something new. Adding a feature for a package that is not
installed yet does nothing at all.

A first install goes through `QNX_SDP_EXTRA_PACKAGES` instead. Once
`write_lockfile` has recorded the package, the feature starts matching it and the
extra entry can go.

## Choosing versions

SDP packages are **not independently versioned**. A Screen build expects a
matching graphics stack; a BSP expects a matching startup library. "The newest of
each" is therefore not automatically a combination that works together, so there
has to be a way to say which version. Three things can, in this order:

| | wins over | use for |
| --- | --- | --- |
| `QNX_SDP_PACKAGE_VERSION[<id>]` | everything | holding one package at a version the rest work with |
| `<id>/<version>` in `QNX_SDP_EXTRA_PACKAGES` | the lockfile | a first install, before the lockfile knows the package |
| the lockfile | — | the normal case |

If none of them says, the version is left empty and p2 resolves whatever it
considers newest.

**Pinning a package you already have.** Keyed by full package id — bitbake
varflag names allow dots:

```bitbake
QNX_SDP_PACKAGE_VERSION[com.qnx.qnx800.target.screen] = "1.0.0.00135T202511211618L"
```

**Installing a package at a chosen version.** The lockfile cannot supply a
version for a package it has never seen, so give one inline, in the same
`<id>/<version>` form the lockfile and `qnxsoftwarecenter_clt` already use:

```bitbake
QNX_SDP_EXTRA_PACKAGES = "com.qnx.qnx800.bsp.hw.raspberrypi_bcm2712_rpi5/0.3.0.00381T202512101351L"
```

Omit the `/<version>` and p2 takes the newest.

To see which versions exist, list the catalogue — the same package often has
five or six:

```bash
qnxsoftwarecenter_clt -list -repository https://www.qnx.com/swcenter
```

### Both mistakes are caught before anything is installed

A pin naming something not selected — a typo, or a package no feature pulls in —
warns rather than silently leaving the version unset:

```
WARNING: QNX_SDP_PACKAGE_VERSION pins nothing that is selected:
com.qnx.qnx800.target.typo. A pin names a full package id, and only affects
a package some feature or QNX_SDP_EXTRA_PACKAGES already selects.
```

A version that does not exist is caught by `resolve_sdp`, which runs p2's
`-verifyOnly` over exactly the set it just printed:

```
Error: Cannot find com.qnx.qnx800.bsp.hw.raspberrypi_bcm2711_rpi4/9.9.9.NOPE,
run with -list to check available units
```

That is the reason to run `-c resolve_sdp` before every `-c install_sdp`: an
unsatisfiable combination fails there, rather than part-way through mutating a
multi-gigabyte tree.

## Tasks

### `bitbake -c check_sdp qnx-sdp`

Compares the installed packages against the lockfile and `QNX_SDP_REQUIRES`.
Read-only, offline (it uses the local repository caches) and takes under a
second.

**Image builds depend on this by default** (`QNX_SDP_CHECK = "0"` to opt out), so
a missing package becomes a named error rather than mkifs failing with
`Host file 'x' not available` and a build-file line number.

It is a no-op when neither a lockfile nor `QNX_QSC_CLT` is configured, so leaving
it on is safe.

### `bitbake -c search qnx-sdp`

Lists what the repository offers, with human-readable names and install status:

```
PACKAGE                                    STATUS     NAME
com.qnx.qnx800.osr.toybox                  installed  QNX® SDP 8.0 Toybox Command-line Utility (0.8.11)
```

Filter with `QNX_SDP_SEARCH`.

> **Limitation:** p2 metadata does not expose file lists, so nothing here can
> answer "which package provides `ls`". Search gets you to the right namespace;
> the last step is still human. (For that specific question the answer is
> `toybox` — QNX 8 ships no standalone `ls`.)

### `bitbake -c search_oss qnx-sdp`

The SDP is not the only source. QNX also publishes prebuilt **open-source**
packages — dbus, glib, openssl, sqlite, Qt — as `.apk` files at
[repo.oss.qnx.com](https://repo.oss.qnx.com), which `qnx-apk.bbclass` installs.
This task is the discovery half: without it, using one means already knowing its
name and channel.

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

> `-R` needs a **real file**. bitbake parses the path as a config file and
> rejects a process substitution (`-R <(echo ...)`) with `ParseError ... not a
> BitBake file`. Set `QNX_OSS_SEARCH` in `local.conf` instead if you prefer.

Each channel publishes an `APKINDEX.tar.gz` — the standard apk index — carrying
name, version, size, licence, homepage and dependencies. **When the result
narrows to four or fewer, the task prints the recipe** rather than describing it:

```bitbake
--- dbus_1.16.2-r2.bb ------------------------
SUMMARY = "Freedesktop.org message bus system"
HOMEPAGE = "https://www.freedesktop.org/Software/dbus"
LICENSE = "AFL-2.1 OR GPL-2.0-or-later"

inherit qnx-apk

QNX_OSS_CHANNEL = "8.0.3/extra"

# Run 'bitbake -c fetch dbus' once and paste the checksum it prints.
SRC_URI[sha256sum] = ""

# Depends on: glib qnx-io-sock
```

Paste that into a `.bb`, run `bitbake -c fetch dbus` once for the checksum, and
it is installable by name via `QNX_IFS_INSTALL` (or `QNX_ROOTFS_INSTALL` for
anything too large for a RAM-resident IFS). The sha256 is the one thing the
index cannot supply — it records a SHA1, and a binary package fetched without a
checksum is neither reproducible nor safe.

The `Depends on:` line is advisory, not automatic: it is the *apk* dependency
graph, and some entries (`qnx-io-sock`) are already in the SDP while others
(`glib`) need a recipe of their own. Read it, do not paste it into `DEPENDS`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QNX_OSS_SEARCH` | `""` | substring filter over name, description and licence |
| `QNX_OSS_SEARCH_CHANNELS` | the four channels QNX serves | which indexes to read |
| `QNX_OSS_REPO` | `https://repo.oss.qnx.com` | set in `conf/layer.conf` |
| `QNX_OSS_ARCH` | `aarch64` | |

The 8.0.3 channels are much the larger (~2400 packages between them); the 8.0.4
pair are a smaller curated set, and `8.0.4/qnx-core` currently answers `403` to
an anonymous index request, which the task reports and skips rather than failing
on.

### `bitbake -c resolve_sdp qnx-sdp`

Shows what `QNX_SDP_FEATURES` resolves to, what is already installed, what would
be added, and runs `-verifyOnly` to prove the combination is satisfiable. Changes
nothing.

### `bitbake -c write_lockfile qnx-sdp`

Records the installed packages as the lockfile. This is how you adopt an existing
SDP, and how you capture the result after an install.

### `bitbake -c install_sdp qnx-sdp`

Installs the selected packages. **Never a dependency of anything**, deliberately:

- it needs the network and your credentials
- it mutates a shared, multi-gigabyte tree that other builds — and possibly other
  checkouts — are using
- the SDP is licensed, so its contents must not travel through an sstate mirror

Run `-c resolve_sdp` first to see what it would do. Afterwards, run
`-c write_lockfile` to record the result.

## Changing a major component: install into a fresh SDP

Moving a component onto a different release train — the hypervisor is the case
that prompted this — is not an upgrade of one package. Components are qualified
against a specific SDP baseline, and the one you want may be *older* than what
you have. Hypervisor 8.0.4 Update 1, released June 2026, requires
`microkernel.core [2.4.0.0,2.4.1)` from February 2026, while a current SDP is on
2.6.0.

Two ways to get this wrong, both of which cost real time:

**Naming one package.** `-installIU <group>/<version>` on its own uninstalls the
old group and takes its dependency closure with it — everything that existed only
to satisfy it. An SDP went from 260 packages and 7.4 GB to 59 and 1.15 GB this
way, losing `qcc`, `mkifs` and `dumpifs`. Recovery is `-c install_sdp` against
the previous lockfile, about ten minutes, but nothing warns you first.

**Reconstructing the baseline by hand.** Pinning packages one at a time to
satisfy each error in turn does not converge: the microkernel pin exposes
`libforksafe_mutex`, which exposes `libcontainer`, which exposes `io-sock`, and
so on. You are re-deriving a set that already exists.

What works is to let p2 solve it, in a directory with nothing in it to preserve:

```bash
qnxsoftwarecenter_clt -url https://www.qnx.com/swcenter \
  -destination /path/to/new-sdp \
  -installIU com.qnx.qnx800.target.hypervisor.group/<version> \
  -setExperimentalEnabled=true -setPolicy=liberal @~/.qnx/qsc-credentials
```

That pulls the component's own qualified baseline — kernel, libc, `io-sock` and
the host toolchain, ~231 packages. Then add what this project needs on top, as
**ids without versions**, so the solver picks versions consistent with what is
already there:

```bash
# what the lockfile wants that the new baseline does not have
comm -13 <(... -listInstalled -destination /path/to/new-sdp | sed 's|/.*||' | sort -u) \
         <(grep '^com.qnx' lockfile | sed 's|/.*||' | sort -u)
```

Anything in that list which genuinely cannot coexist gets dropped rather than
forced. `microkernel.libcontainer` and `os_services.kpipe` both require APIs the
2.4.0 kernel does not provide, and neither appears in any recipe or image here —
check before removing, with `grep` over the layers and over a built `.build` file.

Then point `QNX_SDP_ROOT` at the new tree and run `-c write_lockfile`. The old
SDP is untouched throughout, which is the point: reverting is one line in
`local.conf`.

> `-setPolicy` takes `liberal`, `conservative` or `ultraconservative`. The
> default is conservative, which will not move a package that is already
> installed — so an upgrade appears to succeed while changing nothing.
>
> `liberal` is right for solving a fresh baseline and wrong for touching one
> package in a working SDP: it prefers the newest of everything it is free to
> move, which silently splits matched sets. Changing the kernel this way pulled
> `net.iosock` from `0.3.0.00600` to `0.5.0.00015` while every module —
> `modsphy`, `devspci`, `devsfdt`, `vdevpeernet` — stayed on the older train.
> io-sock then loaded and could `dlopen` none of them, which on the board looks
> like this and reads as a missing file rather than a version split:
>
> ```
> Unable to access /dev/io-sock/mods-vdevpeer-net.so
> ifconfig: interface cgem0 does not exist
> ```
>
> When an SDP that worked stops working after a package change, diff it against
> the one that worked before theorising:
>
> ```bash
> diff <(qnxsoftwarecenter_clt -listInstalled -destination OLD | sort) \
>      <(qnxsoftwarecenter_clt -listInstalled -destination NEW | sort)
> ```
>
> That named the two changed packages out of 294 in one step.

## Meta-packages anchor more than they look

`target.hypervisor.group` is worth installing *around* rather than through. Its
`[2.4.0.0,2.4.1)` requirement on `microkernel.core` is the group's alone —
`hypervisor.core` itself requires only `libc.so.6`, so taking the group pins the
kernel a release train back for no technical reason, and an older kernel breaks
`pidin` (its introspection client is compiled in, and talks to the kernel).

But the group is not only metadata. It anchors `net.vdevpeernet` (which ships
`vpctl` and `mods-vdevpeer-net.so`), `driver.virtio`, `hypervisor.libhyp` and
the guest BSP. Uninstalling it orphans all four, and p2 then drops
`hypervisor.core`/`extras`/`vdev.devel` too if they were only ever recorded as
dependencies — which is what happens when the group installed them.

So install the leaves *and* what the group anchored, explicitly, in one
transaction. p2 will not promote an already-installed package to a root, so
anything installed as a dependency is fair game for a later garbage collection:
check with `-listInstalledRoots`, and put anything missing in
`QNX_SDP_EXTRA_PACKAGES` — `write_lockfile` records roots only.

> Valid credentials matter more than they look. A wrong password produces
> `HttpUnauthorizedException: Authentication failed` on *downloads* while the
> catalog query still works, which reads as a licensing problem and is not one.

## A recipe can state what it needs

```bitbake
QNX_SDP_REQUIRES = "com.qnx.qnx800.target.utils.debugtools"
```

Verified by `check_sdp` before an image is built, so the failure names the
package instead of surfacing later as a missing file.

## Typical flows

**Adopt an SDP you already have:**

```bash
bitbake -c write_lockfile qnx-sdp     # snapshot what is installed
# commit the lockfile
```

**Add a subsystem you already have packages for:**

```bash
# QNX_SDP_FEATURES += "screen"
bitbake -c resolve_sdp qnx-sdp        # what would change, and is it satisfiable
bitbake -c install_sdp qnx-sdp        # do it
bitbake -c write_lockfile qnx-sdp     # record the result
# commit the lockfile diff
```

**Install a package for the first time.** A feature will not do it — features
filter the lockfile, and the lockfile has never heard of this package. Name it
directly, with a version if the newest is not the one you want:

```bash
# QNX_SDP_EXTRA_PACKAGES = "com.qnx.qnx800.bsp.hw.raspberrypi_bcm2712_rpi5/0.3.0.00381T202512101351L"
bitbake -c resolve_sdp qnx-sdp        # confirms the version exists and the set resolves
bitbake -c install_sdp qnx-sdp
bitbake -c write_lockfile qnx-sdp     # now the lockfile records it
# ...and QNX_SDP_EXTRA_PACKAGES can go: a feature matching it works from here on
```

**Hold a package back because a newer one does not fit the rest:**

```bash
# QNX_SDP_PACKAGE_VERSION[com.qnx.qnx800.target.screen] = "1.0.0.00135T202511211618L"
bitbake -c resolve_sdp qnx-sdp        # -verifyOnly proves the combination is satisfiable
bitbake -c install_sdp qnx-sdp
bitbake -c write_lockfile qnx-sdp
```

**Somebody else changed the lockfile:**

```bash
bitbake -c check_sdp qnx-sdp          # what am I missing
bitbake -c install_sdp qnx-sdp        # catch up
```
