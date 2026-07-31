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
    libdrm.so.2 \
    libWFD.so \
    libmemobj.so \
    libswblit.so \
"

# ---------------------------------------------------------------------------
# Destinations, so that this component puts things where the reference images
# put them
# ---------------------------------------------------------------------------
# Without these, each file lands wherever the SDP happens to keep it -- which for
# most of Screen's libraries is usr/lib, while both reference build files place
# them in /lib. Both directories are on every image's LD_LIBRARY_PATH, so nothing
# failed; the images simply did not match the ones they were modelled on, and a
# script or a document naming an absolute path would have been wrong.
#
# libscrmem, libmemobj and libimg are absent from this list because the SDP
# already keeps them in lib/ and they resolve there by themselves.
QNX_COMPONENT_DEST[screen] = "/bin/screen"
QNX_COMPONENT_DEST[libscreen.so] = "/lib/libscreen.so"
QNX_COMPONENT_DEST[libEGL.so] = "/lib/libEGL.so"
QNX_COMPONENT_DEST[libGLESv2.so] = "/lib/libGLESv2.so"
QNX_COMPONENT_DEST[libgbm.so] = "/lib/libgbm.so"
QNX_COMPONENT_DEST[libWFD.so] = "/lib/libWFD.so"
QNX_COMPONENT_DEST[libswblit.so] = "/lib/libswblit.so"

# libdrm is named by its versioned soname rather than as libdrm.so, and that is
# deliberate. The SDP's usr/lib/libdrm.so points at libdrm.so.1, but everything
# in the graphics stack -- v3d_dri.so, libWFDrpi5.so, screen-alloc-rpi5.so --
# has DT_NEEDED libdrm.so.2, and .so.2 is what the reference images carry. Naming
# the unversioned symlink would drag in the .so.1 chain instead and leave the
# soname anything actually links against to be found by the dependency closure,
# at a different path.
QNX_COMPONENT_DEST[libdrm.so.2] = "/lib/libdrm.so.2"

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

# Two links, and the only entries here that are not files.
#
# libdrm.so: named by soname above, so the unversioned name every other build
# system expects has to be added back. The reference points it at .so.2 as well.
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
# The targets are relative on purpose: a symlink target without a leading slash
# resolves against the link's own directory, so each finds the library staged
# beside it.
QNX_IFS_EXTRA_ENTRIES = "\
[type=link] /lib/libGLESv2.so.2=libGLESv2.so.1\n\
[type=link] /lib/libdrm.so=libdrm.so.2\
"

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
