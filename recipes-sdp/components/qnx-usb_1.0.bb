SUMMARY = "USB host stack"
DESCRIPTION = "io-usb-otg and its host-controller and class drivers, plus \
devb-umass so a USB stick appears as a block device. Nothing here is loaded \
until the startup script starts io-usb-otg."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-block"

QNX_COMPONENT_FILES = "\
    io-usb-otg \
    devb-umass \
    usb \
    devu-hcd-dwc3-xhci.so \
    devh-usb.so \
    mods-usb.so \
    cam-cdrom.so \
    libusbdi.so \
    libusbdci.so \
"

# USB ethernet adapters. io-sock dlopens these by name for `-d axe` and friends,
# the same way it does the on-board NIC drivers -- so a USB NIC is useless
# without them even though the USB stack itself is present.
QNX_COMPONENT_FILES += "devs-axe.so devs-axge.so devs-cdce.so devs-smsc.so"
