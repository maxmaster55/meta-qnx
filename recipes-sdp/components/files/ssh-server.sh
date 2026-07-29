#!/bin/ksh
#
# Generate the host keys if they are absent, then start sshd.
#
# The keys are made on the board rather than shipped in the image: a key baked
# into an image is the same key on every board written from it, which makes the
# host identity worthless and is exactly what a scanner flags.
#
# In the host image /etc/ssh is a symlink to /dev/shmem, so these live in RAM and
# are regenerated each boot -- the fingerprint changes, which ssh will warn
# about. Point /etc/ssh at the data partition for keys that persist.

if [ ! -f /etc/ssh/ssh_host_rsa_key ]
then
    ssh-keygen -q -t rsa -N "" -f /etc/ssh/ssh_host_rsa_key
fi

if [ ! -f /etc/ssh/ssh_host_ecdsa_key ]
then
    ssh-keygen -q -t ecdsa -N "" -f /etc/ssh/ssh_host_ecdsa_key
fi

if [ ! -f /etc/ssh/ssh_host_ed25519_key ]
then
    ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
fi

echo "Starting SSH daemon ..."
/usr/sbin/sshd
