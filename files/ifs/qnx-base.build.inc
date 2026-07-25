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
