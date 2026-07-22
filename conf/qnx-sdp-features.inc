# Feature definitions for a QNX SDP.
#
# A feature maps a name to id patterns, relative to ${QNX_SDP_PKG_PREFIX} unless
# they start with "com.qnx.". Patterns are glob syntax and are matched against
# the lockfile, so a feature says *what* and the lockfile says *which version*.
#
# These follow the SDP's own namespaces, which are already meaningful --
# target.net, target.screen, target.utils and so on -- rather than being a
# curated list. That keeps them stable when QNX reorganises a namespace's
# contents, and it is why a feature is a pattern and not 40 package ids.
#
# A project adds its own without editing this file:
#
#     QNX_SDP_FEATURE[my-thing] = "target.mm.* com.qnx.qnx800.osr.something"
#     QNX_SDP_FEATURES += "my-thing"
#
# To discover what exists:  bitbake -c search qnx-sdp

# --- essential ------------------------------------------------------------
# The OS itself: kernel, libc, base runtime.
QNX_SDP_FEATURE[core] = "target.base.* target.microkernel.* target.os_services.*"

# Host-side compiler, binutils, mkifs, mkxfs and the rest of the build tooling.
# Without this there is nothing to build with.
QNX_SDP_FEATURE[toolchain] = "host.linux.* host.common.* host.qnxsdp_env"

# ls, cat, cp, uname and friends. On QNX 8 these are one multicall binary, which
# is why this is a single package and not an alphabet of them.
QNX_SDP_FEATURE[utils] = "osr.toybox target.utils.*"

# --- subsystems -----------------------------------------------------------
QNX_SDP_FEATURE[networking] = "target.net.*"
QNX_SDP_FEATURE[filesystems] = "target.fs.*"
QNX_SDP_FEATURE[storage] = "target.driver.* target.sf.*"
QNX_SDP_FEATURE[pci] = "target.pci.*"
QNX_SDP_FEATURE[usb] = "target.usb.*"
QNX_SDP_FEATURE[security] = "target.security.*"
QNX_SDP_FEATURE[connectivity] = "target.connectivity.*"

# --- graphics and multimedia ---------------------------------------------
# Large. Screen alone is ~70 packages.
QNX_SDP_FEATURE[screen] = "target.screen.*"
QNX_SDP_FEATURE[multimedia] = "target.mm.*"
QNX_SDP_FEATURE[audio] = "target.sound.*"

# --- virtualisation -------------------------------------------------------
# The hypervisor itself, for a host image.
QNX_SDP_FEATURE[hypervisor] = "target.hypervisor.*"

# Guest BSPs, for building images that run under it.
QNX_SDP_FEATURE[hypervisor-guest-arm] = "bsp.hypervisor_guest_arm"
QNX_SDP_FEATURE[hypervisor-guest-x86] = "bsp.hypervisor_guest_x86"

# --- development ----------------------------------------------------------
QNX_SDP_FEATURE[debug] = "target.utils.debugtools target.utils.valgrind"
QNX_SDP_FEATURE[python] = "target.utils.python3 host.linux.x86_64.python3"

# --- boards ---------------------------------------------------------------
# Board support packages. Which ones exist depends on your licence.
QNX_SDP_FEATURE[bsp-hw] = "bsp.hw.*"
