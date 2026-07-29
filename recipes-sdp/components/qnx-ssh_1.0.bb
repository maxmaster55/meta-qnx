SUMMARY = "OpenSSH server and client, with the helpers sshd actually execs"
DESCRIPTION = "sshd, ssh, scp and ssh-keygen are the visible half; sshd-session \
and sftp-server are the half that makes them work. sshd forks a per-connection \
sshd-session, so an image with sshd but not sshd-session accepts a connection \
and then drops it -- which reads like an authentication problem and is not one."
LICENSE = "CLOSED"

inherit qnx-sdp-component

DEPENDS += "qnx-base-runtime qnx-io-sock"

QNX_COMPONENT_FILES = "\
    sshd \
    ssh \
    scp \
    ssh-keygen \
    sshd-session \
    sftp-server \
    ssh-keysign \
    ssh-pkcs11-helper \
    ssh-sk-helper \
    libssl.so \
"

# sshd refuses to start if its host keys are world-readable, and refuses to
# accept a connection at all without a privilege-separation directory.
QNX_COMPONENT_ATTR[sshd] = "uid=0 gid=0 perms=0755"

# usr/libexec is not on mkifs's search path, so a bare name there resolves at
# parse time (the component resolver looks in it) and then fails at image time
# with "Host file 'sshd-session' not available". Each needs the directory named
# explicitly -- the same [search=...] the reference build file uses.
QNX_SSH_LIBEXEC = "search=${QNX_TARGET}/${QNX_PROCESSOR}/usr/libexec"
QNX_COMPONENT_ATTR[sshd-session] = "${QNX_SSH_LIBEXEC} uid=0 gid=0 perms=0755"
QNX_COMPONENT_ATTR[sftp-server] = "${QNX_SSH_LIBEXEC} uid=0 gid=0 perms=0755"
QNX_COMPONENT_ATTR[ssh-keysign] = "${QNX_SSH_LIBEXEC} uid=0 gid=0 perms=0755"
QNX_COMPONENT_ATTR[ssh-pkcs11-helper] = "${QNX_SSH_LIBEXEC} uid=0 gid=0 perms=0755"
QNX_COMPONENT_ATTR[ssh-sk-helper] = "${QNX_SSH_LIBEXEC} uid=0 gid=0 perms=0755"

# The start script is a real file rather than an inline mkifs block. An inline
# block would be a bitbake string, and a shell script is full of ${...} that
# bitbake would try to expand as its own variables -- ssh_host_${t}_key becomes
# ssh_host__key, silently.
SRC_URI = "file://ssh-server.sh"
S = "${WORKDIR}"

QNX_SSH_STAGE = "${QNX_STAGE_DIR}/ssh"

do_install() {
	install -d ${D}${QNX_SSH_STAGE}
	install -m 0744 ${WORKDIR}/ssh-server.sh ${D}${QNX_SSH_STAGE}/ssh-server.sh
}

# /etc/ssh is a link to /dev/shmem so the generated host keys land in RAM -- an
# IFS is read-only, and ssh-keygen has to be able to write. sshd_config goes to
# the same place for the same reason.
#
# sshd also needs a privilege-separation directory to exist before it will
# accept a connection at all: without /var/chroot/sshd the daemon starts and
# every login fails, which reads like an authentication problem.
#
# PermitRootLogin is yes because launching a hypervisor guest needs root, and
# the reference image made the same call. Not a default to keep on a device that
# faces anything.
QNX_IFS_EXTRA_ENTRIES = "\
[type=dir uid=0 gid=0 dperms=0755] /var/chroot\n\
[type=dir uid=0 gid=15 dperms=0755] /var/chroot/sshd\n\
[type=link] /etc/ssh = /dev/shmem\n\
/dev/shmem/sshd_config = {\n\
PermitRootLogin yes\n\
AuthorizedKeysFile      .ssh/authorized_keys\n\
Subsystem       sftp    /usr/libexec/sftp-server\n\
}\n\
[perms=0744] /proc/boot/.ssh-server.sh=@QNX_IFS_SYSROOT@${QNX_SSH_STAGE}/ssh-server.sh\
"
