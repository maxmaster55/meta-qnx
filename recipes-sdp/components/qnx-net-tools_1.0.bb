SUMMARY = "Network diagnostics and configuration tools"
DESCRIPTION = "ping, netstat, tcpdump and the rest -- what you reach for when an \
interface is up but traffic is not flowing. None of these are needed to boot; \
they are needed to work out why something did not."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-io-sock"

QNX_COMPONENT_FILES = "\
    ping \
    netstat \
    arp \
    tcpdump \
    traceroute \
    traceroute6 \
    sockstat \
    ifmcstat \
    ifwatchd \
    ip6addrctl \
    ndp \
    libncursesw.so \
"

# Present only when the SDP carries the matching packages: fs-nfs3 comes with
# the NFS client, the wpa_* tools with the supplicant, and libxo/librpc are
# pulled in by some SDP layouts and not others.
QNX_COMPONENT_FILES += "fs-nfs3 wpa_cli wpa_passphrase libxo.so librpc.so"
QNX_COMPONENT_OPTIONAL = "fs-nfs3 wpa_cli wpa_passphrase libxo.so librpc.so"

# dhcpcd's runtime pieces. The daemon itself is in qnx-io-sock; these are what it
# reads and execs, and they live under ${QNX_TARGET}/etc and /sbin rather than a
# processor tree, so they are named by absolute path.
#
# 20-resolv.conf is the hook that writes /etc/resolv.conf when a lease arrives --
# without it DHCP succeeds and name resolution still does not work, which is a
# uniquely annoying way to fail.
QNX_IFS_EXTRA_ENTRIES = "\
/etc/dhcpcd.conf=${QNX_TARGET}/etc/dhcpcd.conf\n\
/sbin/dhcpcd-run-hooks=${QNX_TARGET}/sbin/dhcpcd-run-hooks\n\
/sbin/dhcpcd-hooks/20-resolv.conf=${QNX_TARGET}/sbin/dhcpcd-hooks/20-resolv.conf\
"
