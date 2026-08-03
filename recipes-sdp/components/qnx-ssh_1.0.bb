SUMMARY = "OpenSSH server and client, with the helpers sshd actually execs"
DESCRIPTION = "sshd, ssh, scp and ssh-keygen are the visible half; sshd-session \
and sftp-server are the half that makes them work. sshd forks a per-connection \
sshd-session, so an image with sshd but not sshd-session accepts a connection \
and then drops it -- which reads like an authentication problem and is not one."
LICENSE = "CLOSED"

inherit qnx-sdp-component

# qnx-login for pam_qnx.so and the /etc/pam.d directory: this sshd authenticates
# through PAM, so without that component every password is rejected no matter
# what /etc/shadow says.
DEPENDS += "qnx-base-runtime qnx-io-sock qnx-login"

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

# Where the generated host keys are kept, and how long to wait for that
# directory to exist.
#
# It has to be on a writable filesystem that survives a reboot, or the board
# gets a new identity every boot and ssh reports the host key as changed --
# which is the same thing it says when someone is impersonating the board, so
# it is worth not crying wolf. The image that carries a data partition creates
# this on it: see qnx-host-data.build.in in meta-qnx-hyp.
#
# The wait exists because the boot script starts sshd long before the data
# partition is mounted -- the SD driver has not been started at that point. It
# costs nothing, since that start is backgrounded. An image with no data
# partition (a guest, say) simply never sees the directory appear, takes the
# ephemeral fallback and says so.
QNX_SSH_KEYDIR ?= "/var/ssh"
QNX_SSH_KEYDIR_WAIT ?= "60"

do_install() {
	install -d ${D}${QNX_SSH_STAGE}
	install -m 0744 ${WORKDIR}/ssh-server.sh ${D}${QNX_SSH_STAGE}/ssh-server.sh

	# The script is referenced by the IFS record below rather than being an
	# inline block, so the template's @MARKER@ pass never sees it -- the
	# substitution has to happen here instead.
	sed -i \
		-e 's|@QNX_SSH_KEYDIR@|${QNX_SSH_KEYDIR}|g' \
		-e 's|@QNX_SSH_KEYDIR_WAIT@|${QNX_SSH_KEYDIR_WAIT}|g' \
		${D}${QNX_SSH_STAGE}/ssh-server.sh

	if grep -q '@QNX_SSH' ${D}${QNX_SSH_STAGE}/ssh-server.sh; then
		bbfatal "ssh-server.sh still has unexpanded markers after substitution"
	fi
}

do_install[vardeps] += "QNX_SSH_KEYDIR QNX_SSH_KEYDIR_WAIT"

# /etc/ssh is a link to /dev/shmem because sshd_config has to be somewhere
# writable and an IFS is read-only.
#
# The host keys are NOT here any more -- they are in QNX_SSH_KEYDIR above, on
# the data partition, because keys in RAM are regenerated every boot. sshd is
# told about them with -h rather than through this file, so where the keys live
# and where the configuration lives stay independent.
#
# sshd also needs a privilege-separation directory to exist before it will
# accept a connection at all: without /var/chroot/sshd the daemon starts and
# every login fails, which reads like an authentication problem.
#
# PermitRootLogin is yes because launching a hypervisor guest needs root, and
# the reference image made the same call. Not a default to keep on a device that
# faces anything.
#
# UsePAM yes and /etc/pam.d/sshd are what make a password work at all here, and
# neither is optional. Without them every login is refused, with the correct
# password, in a way that is indistinguishable from a wrong one:
#
#     root@192.168.2.2's password:
#     Permission denied, please try again.
#
# The reason is the hash format. QNX writes /etc/shadow entries as
#
#     root:@S@<base64 hash>@<base64 salt>:...
#
# and @S@ is QNX's own format, not a crypt(3) one. Exactly one thing in the SDP
# can verify it -- pam_qnx.so. sshd cannot, and neither can libc:
#
#     $ strings pam_qnx.so.2 | grep -c @S@    ->  1
#     $ strings sshd         | grep -c @S@    ->  0
#     $ strings libc.so.6    | grep -c @S@    ->  0
#
# OpenSSH defaults to UsePAM no (the SDP's own stock sshd_config has it
# commented out at that value), so out of the box sshd checks the password with
# crypt(), crypt() cannot parse @S@, and the comparison fails for every password
# anyone could type. Turning PAM on routes the check through pam_qnx.so, which
# is the only thing that understands what is in the file.
#
# This is why the reference image cannot have had working root ssh either: it
# ships neither the pam.d/sshd file nor UsePAM. Its README documenting
# root/root is describing the console.
#
# The pam.d/sshd contents are the SDP's own pam.d/login verbatim: one pam_qnx.so
# per management group. It goes in this component rather than qnx-login because
# it is sshd's file -- an image with a console login and no ssh has no use for
# it. qnx-login is what creates /etc/pam.d and supplies pam_qnx.so, so both have
# to be installed for either to be any use, which is why it is now a DEPENDS.
QNX_IFS_EXTRA_ENTRIES = "\
[type=dir uid=0 gid=0 dperms=0755] /var/chroot\n\
[type=dir uid=0 gid=15 dperms=0755] /var/chroot/sshd\n\
[type=link] /etc/ssh = /dev/shmem\n\
[uid=0 gid=0 perms=0644] /etc/pam.d/sshd = {\n# The PAM configuration file for the 'sshd' service\n\
\n\
auth requisite pam_qnx.so\n\
\n\
account requisite pam_qnx.so\n\
\n\
session requisite pam_qnx.so\n\
\n\
password requisite pam_qnx.so\n\
}\n\
/dev/shmem/sshd_config = {\n\
PermitRootLogin yes\n\
UsePAM yes\n\
PasswordAuthentication yes\n\
KbdInteractiveAuthentication yes\n\
AuthorizedKeysFile      .ssh/authorized_keys\n\
Subsystem       sftp    /usr/libexec/sftp-server\n\
}\n\
[perms=0744] /proc/boot/.ssh-server.sh=@QNX_IFS_SYSROOT@${QNX_SSH_STAGE}/ssh-server.sh\
"
