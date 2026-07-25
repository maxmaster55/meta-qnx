################################################################################
## Base filesystem layout and utilities -- shared by every IFS image.
##
## Included with:   #include qnx-base.build.inc
##
## The console link is the only thing here that varies between images, and it is
## a variable: a guest's console is a virtio console (/dev/vcon1), a hypervisor
## host's is the board's real UART (/dev/ser10). qnx-ifs.bbclass defaults
## QNX_CONSOLE_DEV to the guest case; an image with real hardware overrides it.
##
## ls, cat, uname and the rest are NOT listed here. QNX 8 ships no standalone
## versions of them -- they are all one toybox multicall binary, which
## qnx-ifs.bbclass adds automatically along with a link per command (see
## QNX_IFS_TOYBOX_CMDS). Listing them here would be a duplicate-entry error.
################################################################################

[type=link] /bin/sh=/bin/ksh
[type=link] /tmp=/dev/shmem
[type=link] /dev/console=@QNX_CONSOLE_DEV@
[type=link] /var/log=/tmp
[type=link] /usr/tmp=/tmp

# The shell, and the four utilities you actually need when something has gone
# wrong on the target: what is running, wait for a path, kill it, mount a disk.
/bin/ksh=ksh
/bin/pidin=pidin
/bin/waitfor=waitfor
/bin/slay=slay
/bin/mount=mount
