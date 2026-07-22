# Cookbook

Worked examples, roughly in order of increasing complexity. Every one of these is either a
real recipe in this layer or in `meta-qnx-hyp`.

- [A hello-world application](#a-hello-world-application)
- [Adding it to an image](#adding-it-to-an-image)
- [An application with a makefile](#an-application-with-a-makefile)
- [A CMake application](#a-cmake-application)
- [A library other recipes link against](#a-library-other-recipes-link-against)
- [A driver or resource manager](#a-driver-or-resource-manager)
- [Permissions and ownership](#permissions-and-ownership)
- [Symlinks](#symlinks)
- [Config files](#config-files)
- [Putting a file somewhere unusual](#putting-a-file-somewhere-unusual)
- [A new image](#a-new-image)
- [A board that needs binaries the SDP lacks](#a-board-that-needs-binaries-the-sdp-lacks)
- [Debugging what ended up in an image](#debugging-what-ended-up-in-an-image)

---

## A hello-world application

The minimum. Compile with `qcc`, install into the stage tree, done.

```bitbake
SUMMARY = "Hello world for QNX"
LICENSE = "CLOSED"

SRC_URI = "file://qnx-hello.c"

inherit qnx-sdp

# scarthgap has no UNPACKDIR (that arrived in styhead), so file:// sources are
# unpacked straight into WORKDIR.
S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} -o qnx-hello qnx-hello.c
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 qnx-hello ${D}${QNX_STAGE_BINDIR}/qnx-hello
}
```

Note what is **absent**: no path inside the image, no file list, no mention of a `.build`
file. The `/bin/qnx-hello` entry is derived from what `do_install` staged.

## Adding it to an image

One word:

```bitbake
QNX_IFS_INSTALL = "qnx-hello"
```

To also run it at boot, in the *application* recipe:

```bitbake
QNX_IFS_STARTUP_CMD = "qnx-hello"
```

## An application with a makefile

If the project already cross-compiles for QNX, drive it as-is.

```bitbake
inherit qnx-sdp

# Command-line variables beat the makefile's own assignments, which is what routes
# the build through the compiler this class configured.
EXTRA_OEMAKE = "CC='${CC}' CXX='${CXX}'"

do_compile() {
	oe_runmake -C ${S}
}

do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 ${B}/shm_chunker ${D}${QNX_STAGE_BINDIR}/shm_chunker
}
```

> **Do not blindly pass `CFLAGS`.** Many QNX makefiles use simple assignment
> (`CFLAGS := -Vgcc_ntoaarch64le -std=gnu11 ...`), so overriding it from the command line
> discards the `-std` and `-V` flags along with everything else. Pass `CC`/`CXX` and leave
> `CFLAGS` alone unless you know the makefile appends rather than assigns.

## A CMake application

```bitbake
inherit qnx-cmake

# ...and that may be all. If the project's install() rules already target
# ${CMAKE_SYSTEM_PROCESSOR}/sbin and usr/include -- the QNX convention -- they land
# correctly with no do_install here at all.
```

Real example: `rpi-gpio` in `meta-qnx-hyp` has **no install code**, because upstream
already does:

```cmake
install(TARGETS ${PROJECT_NAME} DESTINATION ${CMAKE_SYSTEM_PROCESSOR}/sbin)
install(FILES ${PUBLIC_HEADER} DESTINATION usr/include/sys)
```

which with the prefix set to the stage tree puts the binary in the image and the header in
the sysroot only.

If the project needs options:

```bitbake
OECMAKE_EXTRA_ARGS = "-DBUILD_TESTING=OFF -DUSE_FOO=ON"
OECMAKE_BUILD_TYPE = "Debug"
```

## A library other recipes link against

Install the library into the stage lib dir and its headers into the stage include dir:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_LIBDIR} ${D}${QNX_STAGE_INCLUDEDIR}
	install -m 0644 libmine.so.1.0.0 ${D}${QNX_STAGE_LIBDIR}/
	ln -sf libmine.so.1.0.0 ${D}${QNX_STAGE_LIBDIR}/libmine.so.1
	ln -sf libmine.so.1      ${D}${QNX_STAGE_LIBDIR}/libmine.so
	install -m 0644 mine.h   ${D}${QNX_STAGE_INCLUDEDIR}/
}
```

The consumer needs one line:

```bitbake
DEPENDS = "libmine"
```

and gets `-I`/`-L` pointing at them automatically. The header goes to the sysroot only; the
`.so` chain enters images as one real file plus `[type=link]` entries, not three copies.

## A driver or resource manager

Start early, and make the ordering mean something:

```bitbake
QNX_IFS_STARTUP_CMD = "rpi_gpio &"
QNX_IFS_STARTUP_PRIORITY = "300"
QNX_IFS_STARTUP_WAITFOR = "/dev/gpio"
```

`&` means the startup script continues the moment it forks — long before
`resmgr_attach()` has registered the device. Priority orders the commands;
`waitfor` is what actually blocks until the node exists. Use both.

Generated result:

```text
### rpi-gpio prio=300
rpi_gpio &
waitfor /dev/gpio 5
### qnx-hello prio=500
qnx-hello
```

## Permissions and ownership

```bitbake
QNX_IFS_ATTR[rpi_gpio] = "uid=0 gid=0 perms=4755"     # setuid root
QNX_IFS_DEFAULT_ATTR   = "uid=0 gid=0"                # all of this recipe's entries
```

Any mkifs record attribute works — the value is passed through verbatim:

```bitbake
QNX_IFS_ATTR[bigfile]   = "data=copy"      # copy rather than reference
QNX_IFS_ATTR[secret.so] = "perms=0400"
QNX_IFS_ATTR[fw.bin]    = "sha512"
```

Keys are **basenames**. `QNX_IFS_ATTR[/sbin/rpi_gpio]` is a parse error — bitbake varflag
names cannot contain `/`.

Verify with `dumpifs -v`:

```
sbin/rpi_gpio    gid=0 uid=0 mode=04755
```

## Symlinks

If you stage the target yourself, just make a real symlink — it is picked up automatically:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_BINDIR}
	install -m 0755 myapp ${D}${QNX_STAGE_BINDIR}/myapp
	ln -sf myapp ${D}${QNX_STAGE_BINDIR}/myapp-alias
}
```

→ `[type=link] /bin/myapp-alias=myapp`

Use a **relative** target (`ln -sf myapp ...`), not `ln -sf ${QNX_STAGE_BINDIR}/myapp ...`,
which would bake a build-host path into the image.

If the target is not something you staged (`/tmp`, `/dev`, another recipe's file):

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[type=link] /var/log=/tmp"
```

Several entries need a literal `\n` — bitbake does not process escapes, and a line
continuation collapses to a space:

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[type=link] /var/log=/tmp\n[type=link] /etc/x=/tmp/x"
```

> Only symlinks to **files** are detected automatically. `os.walk` reports symlinked
> *directories* separately, so those need an explicit entry.

## Config files

Stage a real file and give it permissions:

```bitbake
do_install() {
	install -d ${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR}/etc
	install -m 0644 myapp.conf ${D}${QNX_STAGE_DIR}/${QNX_PROCESSOR}/etc/
}
```

`etc` is **not** on mkifs's search path, so this warns and you must place it explicitly:

```bitbake
QNX_IFS_EXTRA_ENTRIES = "[perms=0644] /etc/myapp.conf=${WORKDIR}/myapp.conf"
```

Or write the body inline in the image template, which is what the project's own build files
do for small scripts:

```
[perms=0744] /proc/boot/.start.sh = {
#!/bin/ksh
echo hello
}
```

## Putting a file somewhere unusual

```bitbake
QNX_IFS_DEST[myapp] = "/proc/boot/myapp"
```

`/proc/boot` is useful for things the startup script runs before any filesystem is mounted.

## A new image

```bitbake
SUMMARY = "My QNX image"
LICENSE = "CLOSED"

SRC_URI = "file://my-image.build.in"

inherit qnx-ifs

S = "${WORKDIR}"
B = "${WORKDIR}/build"

QNX_IFS_NAME = "my-image"
QNX_IFS_TEMPLATE = "${S}/my-image.build.in"

QNX_IFS_INSTALL = "qnx-hello rpi-gpio"

do_configure[noexec] = "1"
do_compile[noexec] = "1"
```

Minimal template:

```
[-optional]
[+keeplinked]
[image=@QNX_IMAGE_ADDR@]

[virtual=@QNX_IMAGE_VIRTUAL@] boot = {
    @QNX_STARTUP@ @QNX_STARTUP_ARGS@
    PATH=@QNX_IFS_PATH@ LD_LIBRARY_PATH=@QNX_IFS_LD_LIBRARY_PATH@ @QNX_KERNEL@ @QNX_KERNEL_ARGS@
}

[+script] startup-script = {
    SYSNAME=nto
    procmgr_symlink ../../proc/boot/ldqnx-64.so.2 /usr/lib/ldqnx-64.so.2
    pipe
    slogger2

    devc-virtio 0x20000000,42
    waitfor /dev/vcon1 4
    reopen /dev/vcon1

@QNX_IFS_STARTUP@

    [+session] ksh &
}

[uid=0 gid=0]
[type=link] /bin/sh=/bin/ksh
[type=link] /tmp=/dev/shmem

@QNX_IFS_FILES@

/sbin/devc-virtio=devc-virtio
/bin/ksh=ksh
```

For a different boot environment — a hypervisor host rather than a guest — override the
boot variables in the recipe:

```bitbake
QNX_IMAGE_ADDR = "0x80000"
QNX_IMAGE_VIRTUAL = "${QNX_PROCESSOR},raw -compress"
QNX_STARTUP = "startup-bcm2712-rpi5"
QNX_STARTUP_ARGS = "-v -u reg -a -W 5000 -Q enable,el1-host"
```

The same template works for both.

## A board that needs binaries the SDP lacks

BSP drivers are often built outside the SDP. Add their install tree as another search root:

```bitbake
QNX_IFS_EXTRA_ROOTS = "${QNX_PROJECT_SRC}/qnx_host/install"
```

Roots are searched left to right, before `$QNX_TARGET`. The tree must mirror
`$QNX_TARGET`'s layout (`aarch64le/sbin/...`).

Nested directories need a subpath, because the search path is flat — `lib/dll` is searched,
`lib/dll/pci` is not:

```
/lib/dll/pci/pci_slog2.so=pci/pci_slog2.so
```

## Debugging what ended up in an image

**Read the generated build file first.** It is deployed next to the image and is the single
answer to "why is this here":

```bash
less tmp/deploy/images/qnx-aarch64le/my-image.build
```

Then:

```bash
dumpifs my-image.ifs                    # contents
dumpifs -v my-image.ifs                 # ...with uid/gid/mode
dumpifs -b my-image.ifs                 # basenames only
bitbake -c generate_buildfile my-image  # regenerate without running mkifs
```

### Common errors

| Message | Meaning |
| --- | --- |
| `Host file 'x' not available` | mkifs could not find `x` in any `-r` root or `$QNX_TARGET`. If it is `ls`/`cat`/`uname`, that is toybox — see `QNX_IFS_TOYBOX_CMDS`. |
| `'x' is in QNX_IFS_INSTALL but contributes nothing` | typo, or a recipe that never installed into `${QNX_STAGE_DIR}` |
| `QNX_IFS_ATTR[x] matched no staged file` | key is not a staged basename |
| `... is outside the mkifs search path` | staged somewhere mkifs cannot find by bare name; use `QNX_IFS_EXTRA_ENTRIES` |
| `unparsed line: 'QNX_IFS_ATTR[/bin/x] = ...'` | varflag keys cannot contain `/` — use the basename |
