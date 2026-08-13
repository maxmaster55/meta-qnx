################################################################################
## Base filesystem layout -- shared by every IFS image.
##
## Included with:   #include qnx-base.build.inc
##
## Almost nothing is left here on purpose. The shell, the loader, the services
## the startup preamble launches and libqcrypto's provider selection all moved
## into the qnx-base-runtime *recipe*, so an image installs them by name:
##
##     QNX_IFS_INSTALL += "qnx-base-runtime"
##
## What stays is the one entry that cannot live in a recipe, because it is not a
## property of any component: the console. A guest's console is a virtio console
## (/dev/vcon1), a hypervisor host's the board's real UART (/dev/ser10), and only
## the image knows which. qnx-ifs.bbclass defaults QNX_CONSOLE_DEV to the guest
## case; an image with real hardware overrides it.
################################################################################

[type=link] /dev/console=@QNX_CONSOLE_DEV@

################################################################################
## The shell's environment file.
##
## qnx-startup-preamble.build.inc sets ENV=/etc/profile, which ksh sources for
## every interactive shell. Without the file that is silently a no-op: the boot
## script's own PATH and LD_LIBRARY_PATH come from the boot line and work, but a
## shell you start later -- over ssh, or a second one on the console -- gets
## neither, and binaries fail to find their libraries for no visible reason.
##
## The paths mirror QNX_IFS_PATH and QNX_IFS_LD_LIBRARY_PATH, which is why they
## are markers rather than literals: an image that changes one would otherwise
## have a profile disagreeing with its own boot line.
##
## QNX_IFS_ENV lands here for the same reason, and in the startup preamble as
## well: the boot script's environment and an interactive shell's are two
## different things, and a variable set in only one of them produces a program
## that works from the boot script and not from the prompt, or the reverse.
################################################################################
/etc/profile = {
export HOME=/
export SYSNAME=nto
export TERM=qansi
export PATH=@QNX_IFS_PATH@
export LD_LIBRARY_PATH=@QNX_IFS_LD_LIBRARY_PATH@
@QNX_IFS_PROMPT_PROFILE@
@QNX_IFS_HISTORY_PROFILE@
@QNX_IFS_ENV_PROFILE@
}

# esh reads this on startup. Empty in the reference image and empty here -- but
# it has to exist: esh treats an absent file as an error rather than as no
# configuration.
/etc/esh = {
}
