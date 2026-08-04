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

# ---------------------------------------------------------------------------
# Key-based login, in both directions
# ---------------------------------------------------------------------------
# These are about USER keys, not the host keys above -- who may log in without
# a password, and what identity this machine presents when it logs in elsewhere.
# Both are empty by default: an image says what it wants.
#
#   QNX_SSH_AUTHORIZED_KEYS   public key lines, one per key, that may log in as
#                             root. Written to /root/.ssh/authorized_keys. A
#                             public key is not a secret, so these are literals
#                             an image or a layer can state outright.
#
#   QNX_SSH_IDENTITY          path on the BUILD HOST to a private key, installed
#                             as /root/.ssh/id_ed25519 at 0600. This one is a
#                             secret, which is why it is a path rather than a
#                             literal and why nothing in this tree sets it: it
#                             belongs in local.conf, beside QNX_SDP_ROOT, and
#                             the key file stays outside the layer.
#
# hms is what needs both halves. It ssh's from the host into each guest to
# manage it, so the host carries the private key and every guest authorises the
# matching public one -- see meta-qnx-hyp's conf/hms-ssh-key.inc.
QNX_SSH_AUTHORIZED_KEYS ?= ""
QNX_SSH_IDENTITY ?= ""

# Public keys named by file rather than written out. Contents are appended to
# QNX_SSH_AUTHORIZED_KEYS, so the two can be used together -- a project key
# stated in a layer, plus whoever is working on the board today:
#
#     QNX_SSH_AUTHORIZED_KEYS_FILE = "/home/you/.ssh/id_ed25519.pub"
#
# in local.conf, so an operator's own key stays in ~/.ssh and never lands in a
# git-tracked recipe.
QNX_SSH_AUTHORIZED_KEYS_FILE ?= ""

# Where the identity lands, and any other path the SAME key has to be reachable
# at. The extra ones become links, not copies -- it is one key, and two files
# that can drift apart is what this must not become.
#
# The host needs two, because hms asks for it by two different names:
#
#     ssh_key=/root/.ssh/id_ed25519      to reach the guests
#     ota_server_key=/.ssh/id_ed25519    to reach the OTA server
#
# and /.ssh is ~/.ssh there: qnx-base.build.inc sets HOME=/ in /etc/profile,
# even though /etc/passwd gives root /root. Whichever of the two hms happens to
# use, the key is at the end of it.
QNX_SSH_IDENTITY_DEST ?= "/root/.ssh/id_ed25519"
QNX_SSH_IDENTITY_LINKS ?= ""

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
# ssh_config is for ssh going OUT from this machine. /root/.ssh is in the
# read-only IFS, so the client cannot record a host key there and every outbound
# connection ends with
#
#     Failed to add the host to the list of known hosts (/root/.ssh/known_hosts)
#
# It is pointed at QNX_SSH_KEYDIR on the data partition instead, where it
# persists -- which is also what makes it possible to turn
# StrictHostKeyChecking back on rather than passing =no everywhere, as hms
# currently has to.
#
# ${...} rather than an @MARKER@: this is expanded by bitbake in THIS recipe's
# context. The fragment expander resolves markers against the image's datastore,
# where QNX_SSH_KEYDIR is not set.
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
/dev/shmem/ssh_config = {\n\
UserKnownHostsFile      ${QNX_SSH_KEYDIR}/known_hosts\n\
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

# QNX_SSH_AUTHORIZED_KEYS and QNX_SSH_IDENTITY are documented above but acted on
# in qnx-ifs.bbclass, not here. They are per-IMAGE: this component is one recipe
# shared by every image, so a value an image sets never reaches this datastore --
# writing the records here produced nothing at all, silently.
