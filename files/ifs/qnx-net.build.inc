################################################################################
## Networking core -- shared by any image with an interface.
##
## Included with:   #include qnx-net.build.inc
##
## io-sock is the QNX 8 network stack; ifconfig and route are what a startup
## script uses to bring an interface up and point it at a gateway. dhcpcd is
## optional so an image still builds on an SDP installed without it.
##
## The *drivers* are not here, for the same reason as in qnx-block.build.inc:
## a guest loads devs-vtnet_mmio.so for virtio-net, a hypervisor host loads real
## NIC drivers plus mods-vdevpeer-net.so to serve its guests. The image lists the
## driver it has hardware for and includes this for the rest.
################################################################################

/sbin/io-sock=io-sock
/sbin/ifconfig=ifconfig
/sbin/route=route
[+optional] /sbin/dhcpcd=dhcpcd
