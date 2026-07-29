SUMMARY = "HID input stack"
DESCRIPTION = "io-hid and the input libraries Screen reads events through -- a \
keyboard or mouse on the board goes through here. Needs qnx-usb for anything \
plugged into a USB port."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-usb"

QNX_COMPONENT_FILES = "\
    io-hid \
    hidview \
    devi-hid \
    libhiddi.so \
    libgestures.so \
    libinputevents.so \
    libkalman.so \
"
