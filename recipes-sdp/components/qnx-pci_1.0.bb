SUMMARY = "pci-server and the modules it dlopens, minus the board's host bridge"
DESCRIPTION = "Everything about PCI that is the same on every board: the server, \
its bus-configuration and namespace modules, one capability handler per PCI and \
PCIe capability ID, and the diagnostics. A board adds its own pci_hw-* module \
and the config naming it; a guest under qvm uses pci_hw-fdt and needs nothing \
board-specific at all."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# None of this is reachable from DT_NEEDED -- pci-server is built almost
# entirely out of dlopen'd modules -- so the shared-library closure cannot find
# any of it. Shipping the server and a hw module without these gives a
# pci-server that starts, finds no way to enumerate a bus and exits before
# creating /dev/pci, after which every driver behind it fails in terms that
# mention anything but PCI.
#
#   pci_server-*  how the server enumerates buses and builds its namespace
#   pci_cap-*     one module per PCI capability ID, dlopen'd by ID as found
#   pcie_xcap-*   the same for PCIe extended capabilities
#   pci_hw-fdt    the generic device-tree host bridge, which is what a guest
#                 under qvm uses -- a real board overrides it
QNX_COMPONENT_FILES = "\
    pci-server \
    pci-connector \
    pci-tool \
    libpci.so \
    pci/pci_bkwd_compat.so \
    pci/pci_strings.so \
    pci/pci_server-buscfg-generic.so \
    pci/pci_server-buscfg-hotplug.so \
    pci/pci_server-buscfg2-generic.so \
    pci/pci_server-buscfg2-hotplug.so \
    pci/pci_server-enable_features.so \
    pci/pci_server-event_handler.so \
    pci/pci_server-namespace.so \
    pci/pci_cap-0x01.so \
    pci/pci_cap-0x04.so \
    pci/pci_cap-0x05.so \
    pci/pci_cap-0x07.so \
    pci/pci_cap-0x09-ffffffff.so \
    pci/pci_cap-0x0d.so \
    pci/pci_cap-0x10.so \
    pci/pci_cap-0x10-16c3abcd.so \
    pci/pci_cap-0x10-19570400.so \
    pci/pci_cap-0x11.so \
    pci/pci_cap-0x11-ffffffff.so \
    pci/pci_cap-0x12.so \
    pci/pci_cap-0x13.so \
    pci/pcie_xcap-0x0001.so \
    pci/pcie_xcap-0x0003.so \
    pci/pcie_xcap-0x000b-ffffffff.so \
    pci/pcie_xcap-0x0015.so \
    pci/pci_debug.so \
    pci/pci_debug2.so \
    pci/pci_slog.so \
    pci/pci_slog2.so \
    pci/pci_hw-fdt.so \
"
