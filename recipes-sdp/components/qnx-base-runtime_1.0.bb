SUMMARY = "The QNX runtime every image needs to run anything at all"
DESCRIPTION = "The dynamic loader, the shell and the services procnto's startup \
script launches before anything else: pipe, slogger2, dumper, mqueue and random. \
Also libqcrypto's provider selection, without which random exits and takes \
/dev/random with it. Nothing here is optional in practice -- an image without it \
boots to a kernel and then fails every command, so it is one component rather \
than five."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# The services the startup preamble launches. These are *named* by the script
# and linked against by nothing, so neither the DT_NEEDED closure in
# qnx-ifs.bbclass nor anything else can discover them -- leaving one out is
# silent until the board prints `Unable to start "pipe" (2)`, errno 2, ENOENT.
#
# The loader is NOT listed, and that is a fix rather than an omission. It used to
# be, with QNX_COMPONENT_DEST[ldqnx-64.so.2] = "/ldqnx-64.so.2" -- a leading
# slash, so it landed at the image root. Meanwhile the DT_NEEDED closure in
# qnx-ifs.bbclass places the loader itself, with a bare destination, which is
# /proc/boot. The two never collided because they were different paths, so mkifs
# said nothing and every image carried the loader twice, ~250KB each:
#
#     ldqnx-64.so.2              <- this component, at the image root
#     proc/boot/ldqnx-64.so.2    <- the closure, where it belongs
#
# The reference image has only the second. The closure is the better owner: it
# runs only when the image actually contains dynamic binaries, it resolves the
# name across every search root, and it warns by name if the loader is missing --
# "nothing will run" is worth saying out loud. See QNX_IFS_LOADER.
#
# libc and the rest of the shared libraries are deliberately NOT listed either:
# they are reachable from DT_NEEDED and qnx-ifs.bbclass works the closure out for
# itself. Listing them here would duplicate a list that is already derived, and
# derived lists do not go stale.
QNX_COMPONENT_FILES = "\
    pipe \
    slogger2 \
    dumper \
    mqueue \
    random \
    qcrypto-openssl-3.so \
    ksh \
    pidin \
    waitfor \
    slay \
    mount \
"

# The config file libqcrypto reads to choose a provider. It is not an SDP file,
# so it is written inline rather than named above -- and it has to exist, or
# random gets one step further than it did without the provider module and fails
# differently: "Failed to initialize PRNG ret=22" (EINVAL) from random.c(162)
# instead of random.c(296).
#
# The shell links round out the set: /bin/sh is what every script's shebang
# resolves to, and /tmp on /dev/shmem is where a RAM-resident system puts
# scratch state.
QNX_IFS_EXTRA_ENTRIES = "\
[uid=0 gid=0 perms=0644] /etc/qcrypto.conf = {\n\
openssl-3     tags=*\n\
}\n\
[type=link] /bin/sh=/bin/ksh\n\
[type=link] /tmp=/dev/shmem\n\
[type=link] /var/log=/tmp\n\
[type=link] /usr/tmp=/tmp\
"
