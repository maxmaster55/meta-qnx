SUMMARY = "io-sock, the QNX 8 network stack, with its generic modules"
DESCRIPTION = "The stack, the tools that configure it, the plumbing modules \
every board needs (phy, fdt, phy_fdt) and the name databases its lookups read. \
NIC drivers are not here -- see QNX_COMPONENT_FILES for why."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# Every `-m <name>` on io-sock's command line is a dlopen of mods-<name>.so and
# every `-d <name>` a dlopen of devs-<name>.so. io-sock exits if the first one
# is missing, so a stack started as `io-sock -m phy -m fdt ...` with none of
# these present never creates /dev/io-sock -- and says so nowhere. The failure
# is reported entirely by things downstream: "Address family not supported by
# protocol family" from every ifconfig, "network stack down" from if_up, and
# interfaces that do not exist.
#
# phy/fdt/phy_fdt are generic plumbing. The bus modules (mods-pci, mods-usb) and
# the devs-* NIC drivers belong to the image that has the hardware, so a board
# layer adds a component of its own rather than this one growing a driver list
# that is wrong everywhere except one board.
QNX_COMPONENT_FILES = "\
    io-sock \
    ifconfig \
    route \
    mods-phy.so \
    mods-fdt.so \
    mods-phy_fdt.so \
"

# An SDP installed without the DHCP client is a legitimate configuration.
QNX_COMPONENT_FILES += "dhcpcd"
QNX_COMPONENT_OPTIONAL = "dhcpcd"

# The name databases. These live under ${QNX_TARGET}/etc rather than under a
# processor tree, so they are on no search path and cannot be found by bare
# name -- hence absolute sources rather than QNX_COMPONENT_FILES entries.
#
# Without them sockets still work, but everything resolving a *name* fails:
# getservbyname finds no port, getprotobyname no protocol, and pfctl cannot
# parse a rule that names a service.
QNX_IFS_EXTRA_ENTRIES = "\
/etc/hosts=${QNX_TARGET}/etc/hosts\n\
/etc/services=${QNX_TARGET}/etc/services\n\
/etc/protocols=${QNX_TARGET}/etc/protocols\n\
/etc/netconfig=${QNX_TARGET}/etc/netconfig\n\
/etc/pf.os=${QNX_TARGET}/etc/pf.os\
"
