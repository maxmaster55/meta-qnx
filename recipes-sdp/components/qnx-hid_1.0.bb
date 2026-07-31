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

# /bin, where the reference host image has both, rather than the sbin the SDP
# keeps them in.
#
# Note the reference carries io-hid at BOTH bin/io-hid and sbin/io-hid -- two
# copies of one binary, from two hand-written entries in the same file. Only the
# /bin one is reproduced here: matching a duplicate is not matching a location.
QNX_COMPONENT_DEST[io-hid] = "/bin/io-hid"
QNX_COMPONENT_DEST[hidview] = "/bin/hidview"
