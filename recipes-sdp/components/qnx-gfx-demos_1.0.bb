SUMMARY = "Graphics demos"
DESCRIPTION = "gles2-gears, vkcubepp and vulkaninfo -- how you find out whether \
the GPU is working, as opposed to whether Screen started, which is a different \
question and the one everything else answers."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-screen"

QNX_COMPONENT_FILES = "\
    gles2-gears \
    vkcubepp \
    vulkaninfo \
    libvulkan.so \
"

# Where the reference images put these, rather than where the SDP keeps them
# (usr/bin and usr/lib). Both are on PATH and LD_LIBRARY_PATH, so this is about
# matching the images these were modelled on -- `gles2-gears` is the first thing
# anyone types to check the GPU, and it should be the same path in both.
QNX_COMPONENT_DEST[gles2-gears] = "/bin/gles2-gears"
QNX_COMPONENT_DEST[vkcubepp] = "/bin/vkcubepp"
QNX_COMPONENT_DEST[vulkaninfo] = "/bin/vulkaninfo"
QNX_COMPONENT_DEST[libvulkan.so] = "/lib/libvulkan.so"
