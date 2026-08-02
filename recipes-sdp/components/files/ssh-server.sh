#!/bin/ksh
#
# Wait for somewhere persistent to keep the host keys, generate them if they are
# not already there, then start sshd.
#
# The keys are made on the board rather than shipped in the image: a key baked
# into an image is the same key on every board written from it, which makes the
# host identity worthless and is exactly what a scanner flags.
#
# But making them once is the point. They used to land in /dev/shmem, because
# /etc/ssh is a symlink there and an IFS is read-only -- so every boot produced a
# new identity and every ssh from the same client produced:
#
#     @@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@
#
# which is indistinguishable from the thing that warning exists to report. The
# keys now live in @QNX_SSH_KEYDIR@ on the data partition, and are reused.
#
# The wait is the whole reason this is not simply a path change. This script is
# started from the boot script well before the data partition is mounted -- the
# SD driver has not even been started at that point -- so the directory does not
# exist yet. Waiting here is free: the boot script backgrounds this script, so
# nothing downstream is held up, and sshd was never something the rest of the
# boot depended on.
#
# A board with no data partition still gets ssh, with a warning and the old
# ephemeral behaviour. That is a deliberate fallback: losing remote access on a
# board whose disk did not mount is losing the tool you would use to find out
# why.

KEYDIR=@QNX_SSH_KEYDIR@
WAIT=@QNX_SSH_KEYDIR_WAIT@

x=0
while [ $x -lt $WAIT ]
do
    if [ -d $KEYDIR ]
    then
        break
    fi
    x=$(( $x + 1 ))
    sleep 1
done

if [ ! -d $KEYDIR ]
then
    echo "sshd: $KEYDIR did not appear in ${WAIT}s -- keeping host keys in RAM."
    echo "      ssh will report a changed host key on every boot. Check that the"
    echo "      data partition mounted; see .storage-server.sh."
    KEYDIR=/dev/shmem
fi

for t in rsa ecdsa ed25519
do
    if [ ! -f $KEYDIR/ssh_host_${t}_key ]
    then
        echo "sshd: generating $t host key in $KEYDIR"
        ssh-keygen -q -t $t -N "" -f $KEYDIR/ssh_host_${t}_key
    fi
done

# -h rather than HostKey lines in sshd_config, so that where the keys live and
# where the configuration lives stay independent. sshd_config is still read
# through /etc/ssh, which is in the IFS and read-only; moving the keys must not
# require moving that too.
echo "Starting SSH daemon (host keys in $KEYDIR) ..."
/usr/sbin/sshd \
    -h $KEYDIR/ssh_host_rsa_key \
    -h $KEYDIR/ssh_host_ecdsa_key \
    -h $KEYDIR/ssh_host_ed25519_key
