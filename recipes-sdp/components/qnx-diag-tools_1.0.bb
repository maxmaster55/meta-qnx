SUMMARY = "Debugging, tracing and system inspection tools"
DESCRIPTION = "qconn and pdebug for remote debugging, the tracelogger chain for \
instrumented-kernel traces, slog2info for reading the system log, and the \
handful of QNX-specific inspection utilities that have no Linux equivalent to \
fall back on -- pidin is in the base runtime; these are the rest."
LICENSE = "CLOSED"

inherit qnx-sdp-component

QNX_COMPONENT_FILES = "\
    qconn \
    pdebug \
    tracelogger \
    traceprinter \
    slog2info \
    devctl \
    devinfo \
    rsrcdb_query \
    isend \
    isendrecv \
    hd \
    ldd \
    use \
    top \
    vmstat \
    confstr \
    on \
    kill \
    shutdown \
    getconf \
    setconf \
    libtraceparser.so \
    libslog2parse.so \
    libslog2shim.so \
    libbacktrace.so \
"

# Where the reference host image puts these, rather than where the SDP keeps
# them. traceprinter is in the SDP's usr/bin and the reference has it in
# usr/sbin; libbacktrace is the other way round.
QNX_COMPONENT_DEST[traceprinter] = "/usr/sbin/traceprinter"
QNX_COMPONENT_DEST[libbacktrace.so] = "/usr/lib/libbacktrace.so"

# devc-pty is deliberately NOT listed, though qconn needs a pty: the RPi5 host
# image's own build file already ships it, and a second record is not a harmless
# duplicate -- mkifs stops with "Entry 'sbin/devc-pty' redefined". An image that
# wants qconn and does not already carry devc-pty adds it itself.

# Utilities QNX ships as their own binaries rather than through toybox, so a
# toybox link would not produce them. Optional because most come from the osr.*
# ports, which an SDP installed from feature patterns need not carry -- and one
# absent utility should not take the whole component, and with it qconn and the
# tracing chain, out of the image.
QNX_COMPONENT_FILES += "bunzip2 bzcat ascii crc32 dos2unix unix2dos uudecode uuencode"

# Libraries nothing in the closure reaches but the reference image carries:
# libcatalog backs the message-catalogue calls in libc, libdevice-publisher the
# device-publisher API, libpci_mux the PCI multiplexer pci-connector talks to.
QNX_COMPONENT_FILES += "libcatalog.so libdevice-publisher.so libpci_mux.so"

# Extras that only some SDP layouts carry.
QNX_COMPONENT_FILES += "bc dtach dvtm iperf2 iperf3 libiperf.so server-monitor"
QNX_COMPONENT_OPTIONAL = "bc dtach dvtm iperf2 iperf3 libiperf.so server-monitor \
                          ascii crc32 dos2unix unix2dos uudecode uuencode"
