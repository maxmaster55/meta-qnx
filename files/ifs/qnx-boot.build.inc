################################################################################
## Boot header -- shared by every IFS image.
##
## Included with:   #include qnx-boot.build.inc
##
## This is the part of a build file that is the same for a hypervisor host, a
## guest and a bare test image, because everything that actually differs between
## them is already a variable:
##
##   @QNX_IMAGE_ADDR@       where the loader puts the image
##   @QNX_IMAGE_VIRTUAL@    processor + format ("aarch64le,elf", "aarch64le,raw -compress")
##   @QNX_STARTUP@          the startup program, which is board-specific
##   @QNX_STARTUP_ARGS@     watchdog, hypervisor mode, startup interface
##   @QNX_KERNEL@ / @QNX_KERNEL_ARGS@
##   @QNX_IFS_PATH@ / @QNX_IFS_LD_LIBRARY_PATH@
##
## qnx-ifs.bbclass gives all of them guest-shaped defaults; an image recipe
## overrides the ones it needs. See the host image, which overrides every one.
##
## [-optional]   a missing file is an error, not a silent omission
## [+keeplinked] keep symlinks as symlinks instead of resolving them, so a
##               versioned library chain stays one payload
################################################################################

[-optional]
[+keeplinked]
[image=@QNX_IMAGE_ADDR@]

[virtual=@QNX_IMAGE_VIRTUAL@] boot = {
    @QNX_STARTUP@ @QNX_STARTUP_ARGS@
    PATH=@QNX_IFS_PATH@ LD_LIBRARY_PATH=@QNX_IFS_LD_LIBRARY_PATH@ @QNX_KERNEL@ @QNX_KERNEL_ARGS@
}
