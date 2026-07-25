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
# The loader is the other half: PT_INTERP asks for /usr/lib/ldqnx-64.so.2, which
# the preamble's procmgr_symlink redirects to /proc/boot, so it is placed there
# (see QNX_COMPONENT_DEST below). Without it every dynamically linked binary --
# which is all of them but procnto -- fails with ELIBACC, errno 83.
#
# libc and the rest of the shared libraries are deliberately NOT listed: they
# are reachable from DT_NEEDED and qnx-ifs.bbclass works the closure out for
# itself. Listing them here would duplicate a list that is already derived, and
# derived lists do not go stale.
QNX_COMPONENT_FILES = "\
    ldqnx-64.so.2 \
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

# The loader lands at /proc/boot rather than the /usr/lib the SDP keeps it in.
QNX_COMPONENT_DEST[ldqnx-64.so.2] = "/ldqnx-64.so.2"

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
