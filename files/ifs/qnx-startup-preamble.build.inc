################################################################################
## Startup-script preamble -- shared by every IFS image.
##
## Included INSIDE the [+script] startup-script block, as its first line -- see
## qnx-guest.build.in or qnx-host.build.in for the shape.
##
## CAREFUL: nothing in this file may contain a brace, in a comment or otherwise.
## mkifs does not strip comments inside a script block, so a stray closing brace
## ends the script early and every line after it is read as a file record --
## which surfaces as the memorable "Host file 'nto' not available", SYSNAME=nto
## having become a record. The same restriction applies to any inline script
## block, and is why this header spells out no example.
##
## Every QNX system starts this way, and nothing in it is board- or role-
## specific. It has to come before anything else in the script: procnto starts
## with no dynamic loader path and no services, so until the symlink and these
## managers exist, most commands below would simply fail.
##
##   procmgr_symlink  makes ldqnx-64.so.2 resolvable at its usual path, which is
##                    what lets a dynamically linked binary run at all
##   pipe             pipes, needed by ksh for any command with a |
##   slogger2         the system log, which everything else writes to
##   dumper           writes a core file when a process faults, instead of
##                    losing the crash
##   mqueue           POSIX message queues
##   random           /dev/random, needed by ssh and anything using TLS
################################################################################

    SYSNAME=nto
    TERM=qansi

    ## QNX_IFS_ENV -- the image's own system-wide environment, if it sets any.
    ## Assignments here are inherited by everything the boot script starts and
    ## by the login shell it ends with. /etc/profile in qnx-base.build.inc
    ## carries the same list for shells started later.
@QNX_IFS_ENV_SCRIPT@

    procmgr_symlink ../../proc/boot/ldqnx-64.so.2 /usr/lib/ldqnx-64.so.2

    pipe
    slogger2
    dumper
    mqueue
    random
