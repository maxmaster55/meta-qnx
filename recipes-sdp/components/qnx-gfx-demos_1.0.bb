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
