SUMMARY = "Console login: PAM, the user database and the tools that use it"
DESCRIPTION = "login, su and passwd, the PAM modules they authenticate through, \
and the /etc files without which none of them do anything useful. Not needed for \
a serial console that drops straight to a shell -- needed for ssh, and for any \
system where being root is not automatic."
LICENSE = "CLOSED"

inherit qnx-sdp-component

QNX_COMPONENT_FILES = "\
    login \
    su \
    passwd \
    stty \
    vi \
    pam_deny.so \
    pam_echo.so \
    pam_exec.so \
    pam_group.so \
    pam_permit.so \
    pam_qnx.so \
    pam_rootok.so \
    pam_secpol.so \
    pam_self.so \
    libedit.so \
    libintl.so \
    libiconv.so \
    libpanelw.so \
"

# setuid, or su and passwd cannot do the one thing they exist for.
QNX_COMPONENT_ATTR[login] = "uid=0 gid=0 perms=4755"
QNX_COMPONENT_ATTR[su] = "uid=0 gid=0 perms=4755"
QNX_COMPONENT_ATTR[passwd] = "uid=0 gid=0 perms=4755"

# ---------------------------------------------------------------------------
# The user database
# ---------------------------------------------------------------------------
# These hashes are QNX's own, copied from the published BSP build file. They are
# demo credentials, public knowledge, and are here so a board behaves like the
# reference image rather than being unloggable.
#
# CHANGE THEM before anything leaves a desk. Set QNX_LOGIN_SHADOW to a file of
# your own to replace this wholesale -- the same escape hatch qnx-host-conf uses
# for the wifi PSK, and for the same reason: a credential committed once stays
# in git history after the file is deleted.
QNX_LOGIN_SHADOW ?= ""

QNX_IFS_EXTRA_ENTRIES = "\
[uid=0 gid=0 perms=0644] /etc/passwd = {\n\
root:x:0:0:Superuser:/root:/bin/sh\n\
sshd:x:15:6:sshd:/var/chroot/sshd:/bin/false\n\
qnxuser:x:1000:1000:QNX User:/home/qnxuser:/bin/sh\n\
}\n\
[uid=0 gid=0 perms=0644] /etc/group = {\n\
root:x:0:root\n\
sshd:x:6:\n\
qnxuser:x:1000\n\
}\n\
[uid=0 gid=0 type=dir dperms=0755] /etc/pam.d\n\
[uid=0 gid=0 perms=0644] /etc/pam.d/login=${QNX_TARGET}/etc/pam.d/login\n\
[uid=0 gid=0 perms=0644] /etc/pam.d/passwd=${QNX_TARGET}/etc/pam.d/passwd\n\
[uid=0 gid=0 perms=0644] /etc/pam.d/su=${QNX_TARGET}/etc/pam.d/su\
"

python () {
    shadow = (d.getVar('QNX_LOGIN_SHADOW') or '').strip()
    if shadow:
        d.appendVar('QNX_IFS_EXTRA_ENTRIES',
                    '\\n[uid=0 gid=0 perms=0600] /etc/shadow=' + shadow)
    else:
        d.appendVar('QNX_IFS_EXTRA_ENTRIES', '\\n'.join([
            '',
            '[uid=0 gid=0 perms=0600] /etc/shadow = {',
            'root:@S@NKlWES1quMp1wmqugkUSnFEpPGn58kIs4wQOgDDNs06vimR+bbGPUKM+9P6jbFUzo3Rm+Qe5MS+17xKhwaeJEg==@Mjg5ZTJiMTM0YTRjYTE2ZGFjMDdhZTFlY2NlMDVmNmE=:1468494669:0:0',
            'sshd:*:1231323780:0:0',
            'qnxuser:@S@HZERXjgixvb3157FFeraShhvTVw+10ccUtVUVZbi0fUwpzlzBZFw5gHiFd1XHKit8D39Whe749XAY8fV4P5ANQ==@Y2ZlOTg3M2RhNTM4Y2M2ODY0OWZhODdiNDRkMmU5Nzg=:1468488235:0:0',
            '}',
        ]))
}

# Warned from a postfunc, not the anonymous python above: that runs on every
# parse, so the message would repeat once per recipe in the tree. A postfunc
# rather than do_install:append because do_install here is the class's shell
# function, and python cannot be appended to one.
python qnx_login_warn_shadow() {
    if not (d.getVar('QNX_LOGIN_SHADOW') or '').strip():
        bb.warn("%s: shipping QNX's published demo password hashes -- root and "
                "qnxuser have well-known passwords. Set QNX_LOGIN_SHADOW to your "
                "own /etc/shadow before this leaves a desk." % d.getVar('PN'))
}
do_install[postfuncs] += "qnx_login_warn_shadow"
