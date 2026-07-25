# Managing the SDP

The SDP is not built by Yocto — it is installed by QNX's own
`qnxsoftwarecenter_clt` from QNX's servers. What this layer adds is a way to say
*what* should be in it, check that it is, and make it so.

## Intent vs. resolved

The split follows `package.json` / `package-lock.json`:

| | What it is | Who writes it |
| --- | --- | --- |
| `QNX_SDP_FEATURES` | intent — readable, unpinned | you |
| the **lockfile** | the resolved result: exact ids and versions | `bitbake -c write_lockfile` |

**You never hand-write a version.** p2 (the provisioning engine
`qnxsoftwarecenter_clt` wraps) resolves dependencies, `-verifyOnly` proves a
combination is satisfiable before anything is touched, and the snapshot records
what it actually chose. Two machines with the same lockfile get the same SDP, and
regenerating it is a reviewable diff.

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
bitbake -c search_oss qnx-sdp -R <(echo 'QNX_OSS_SEARCH = "dbus"')
```

```
PACKAGE                      VERSION               SIZE  CHANNEL          DESCRIPTION
dbus                         1.16.2-r2             0.4M  8.0.3/extra      Freedesktop.org message bus system
dbus-dev                     1.16.2-r2             0.0M  8.0.3/extra      Freedesktop.org message bus system (development files)
dbus-glib                    0.114-r0              0.1M  8.0.3/extra      GLib bindings for DBUS
python3-dbus                 1.4.0-r0              0.1M  8.0.3/extra      Python3 bindings for DBUS
```

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

**Add a subsystem:**

```bash
# QNX_SDP_FEATURES += "screen"
bitbake -c resolve_sdp qnx-sdp        # what would change, and is it satisfiable
bitbake -c install_sdp qnx-sdp        # do it
bitbake -c write_lockfile qnx-sdp     # record the result
# commit the lockfile diff
```

**Somebody else changed the lockfile:**

```bash
bitbake -c check_sdp qnx-sdp          # what am I missing
bitbake -c install_sdp qnx-sdp        # catch up
```
