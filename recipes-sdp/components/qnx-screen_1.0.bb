SUMMARY = "QNX Screen: the compositor and its client runtime"
DESCRIPTION = "The screen binary, the libraries an application links against to \
draw, and the blitter/buffer modules Screen dlopens. What is NOT here is a \
display driver -- that is board-specific (drm-rpi5 on a Pi 5, virtio in a guest) \
and comes from whatever provides the hardware."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# screencmd and screeninfo are the tools for asking a running Screen what it
# thinks its displays are -- the first thing worth running when a panel stays
# dark. They belong with the compositor rather than in whichever image happened
# to list them, which is where they used to be.
QNX_COMPONENT_FILES = "\
    screen \
    screencmd \
    screeninfo \
    libscreen.so \
    libscrmem.so \
    libEGL.so \
    libGLESv2.so \
    libgbm.so \
    libdrm.so \
    libWFD.so \
    libmemobj.so \
    libswblit.so \
"

# Screen dlopens these by name from lib/dll. screen-sw is the software
# rasteriser it falls back to with no GPU, screen-stdbuf the default buffer
# allocator, screen-gles2blt the GLES2 blitter -- an image with the libraries
# but not these gets a compositor that starts and cannot composite.
QNX_COMPONENT_FILES += "\
    screen-sw.so \
    screen-stdbuf.so \
    screen-gles2blt.so \
    screen-debug.so \
"

# A compatibility alias, and the only entry here that is not a file.
#
# The SDP ships libGLESv2 with soname libGLESv2.so.1. Some callers ask for
# libGLESv2.so.2 -- the soname the same library has on Linux -- and they ask for
# it by dlopen'ing the literal name, not through DT_NEEDED. That matters twice
# over: the shared-library closure in qnx-ifs.bbclass reads DT_NEEDED, so it
# cannot see this dependency and will not add the library for you, and the
# failure happens at runtime in whatever dlopen'd it rather than at build time.
#
# libepoxy is the one that does it here, which is how qvm dies at guest launch
# with the GPU vdev half-initialised:
#
#     virtio-gpu vdev: init (1024x600 override, virgl 3D)
#     Couldn't open libGLESv2.so.2: Library cannot be found
#
# The reference image carries the same link for the same reason.
#
# The target is relative on purpose: a symlink target without a leading slash
# resolves against the link's own directory, so this finds the libGLESv2.so.1
# staged beside it whichever directory the component resolved into.
QNX_IFS_EXTRA_ENTRIES = "[type=link] /usr/lib/libGLESv2.so.2=libGLESv2.so.1"

# The image codecs libimg loads, one per format.
QNX_COMPONENT_FILES += "\
    libimg.so \
    img_codec_bmp.so \
    img_codec_gif.so \
    img_codec_jpg.so \
    img_codec_png.so \
    img_codec_sgi.so \
    img_codec_tga.so \
    img_codec_tif.so \
"
