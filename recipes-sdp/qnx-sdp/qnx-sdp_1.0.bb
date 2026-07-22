SUMMARY = "Describe, verify and install the contents of a QNX SDP"
DESCRIPTION = "The SDP is installed by QNX's own qnxsoftwarecenter_clt from QNX's \
servers; this recipe says what should be in it, checks that it is, and can make \
it so. Nothing here builds the SDP, and no normal build depends on the install \
task -- see the class header for why."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit qnx-sdp-packages

require conf/qnx-sdp-features.inc

# Nothing to fetch, unpack, configure or compile -- every task here is explicit.
INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"
inherit nopackages

do_fetch[noexec] = "1"
do_unpack[noexec] = "1"
do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_populate_sysroot[noexec] = "1"

S = "${WORKDIR}"
B = "${WORKDIR}/build"

python () {
    # Deliberately no SkipRecipe on a missing SDP: do_install_sdp exists to
    # create one. The individual tasks check what they actually need.
    pass
}

def qnx_sdp_qsc(d, what):
    """Path to qnxsoftwarecenter_clt, or fail with something actionable."""
    import os
    clt = d.getVar('QNX_QSC_CLT')
    if not clt:
        bb.fatal("%s needs QNX_QSC_CLT set to the qnxsoftwarecenter_clt binary, "
                 "e.g.\n"
                 '  QNX_QSC_CLT = "/path/to/qnxsoftwarecenter/qnxsoftwarecenter_clt"'
                 % what)
    if not os.path.isfile(clt):
        bb.fatal("QNX_QSC_CLT '%s' does not exist" % clt)
    return clt

def qnx_sdp_run(d, args, what):
    """Run qnxsoftwarecenter_clt and return stdout.

    Its exit status is not always meaningful, so callers check the output."""
    import subprocess

    clt = qnx_sdp_qsc(d, what)
    cmd = [clt] + args

    # Every task here is noexec except these python ones, so ${B} may not exist.
    workdir = d.getVar('B')
    bb.utils.mkdirhier(workdir)

    bb.note("running %s %s" % (clt, ' '.join(args)))
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              cwd=workdir)
    except OSError as exc:
        bb.fatal("could not run %s: %s" % (clt, exc))

    if proc.returncode != 0:
        bb.warn("%s exited %d\n%s" % (clt, proc.returncode,
                                      proc.stderr.strip()[:2000]))
    return proc.stdout


def qnx_sdp_installed(d):
    """{id: version} currently installed, from -listInstalledRoots.

    Read-only, offline (it uses the local repository caches) and fast."""
    out = qnx_sdp_run(d, ['-listInstalledRoots',
                          '-destination', d.getVar('QNX_SDP_ROOT')],
                      'listing installed packages')
    packages = {}
    for line in out.splitlines():
        line = line.strip()
        if line.startswith('com.qnx.') and '/' in line:
            pkg, version = line.split('/', 1)
            packages[pkg] = version
    return packages


# ---------------------------------------------------------------------------
# check -- is the installed SDP the one this project expects?
# ---------------------------------------------------------------------------
python do_check_sdp() {
    import os

    sdp = d.getVar('QNX_SDP_ROOT')
    if not sdp or not os.path.isdir(os.path.join(sdp, 'target', 'qnx')):
        bb.fatal("QNX_SDP_ROOT '%s' is not a QNX SDP. Set it in local.conf, or "
                 "run 'bitbake -c install_sdp qnx-sdp' to create one." % sdp)

    expected = qnx_sdp_read_lockfile(d)
    required = (d.getVar('QNX_SDP_REQUIRES') or '').split()

    if not expected and not required:
        bb.note("no lockfile and no QNX_SDP_REQUIRES; nothing to check")
        return

    # Package-level verification needs the Software Center tool. Without it the
    # SDP directory check above still ran, which is the important part; say so
    # and carry on rather than failing every build that enabled the check.
    if not d.getVar('QNX_QSC_CLT'):
        bb.note("QNX_QSC_CLT is not set, so package verification is skipped. "
                "Set it to the qnxsoftwarecenter_clt binary to check the SDP "
                "against %s." % (d.getVar('QNX_SDP_LOCKFILE') or 'the lockfile'))
        return

    installed = qnx_sdp_installed(d)
    if not installed:
        bb.fatal("could not list the installed packages; is QNX_QSC_CLT correct?")

    missing = sorted(p for p in expected if p not in installed)
    wrong = sorted('%s (want %s, have %s)' % (p, expected[p], installed[p])
                   for p in expected
                   if p in installed and expected[p] and expected[p] != installed[p])
    unrequired = sorted(p for p in required if p not in installed)

    for pkg in unrequired:
        bb.error("required package not installed: %s" % pkg)
    for pkg in missing:
        bb.error("lockfile package not installed: %s" % pkg)
    for entry in wrong:
        bb.error("version mismatch: %s" % entry)

    if missing or wrong or unrequired:
        bb.fatal("the SDP does not match this project. Run\n"
                 "  bitbake -c install_sdp qnx-sdp\n"
                 "to install what is missing, or -c write_lockfile to adopt "
                 "what is installed.")

    extra = sorted(p for p in installed if p not in expected)
    if extra:
        bb.note("%d package(s) installed beyond the lockfile (harmless): %s"
                % (len(extra), ' '.join(extra[:5]) + (' ...' if len(extra) > 5 else '')))

    bb.note("SDP matches the lockfile: %d package(s)" % len(expected))
}
addtask check_sdp
do_check_sdp[nostamp] = "1"
do_check_sdp[doc] = "Verify the installed SDP against the lockfile"


# ---------------------------------------------------------------------------
# write_lockfile -- adopt what is installed
# ---------------------------------------------------------------------------
python do_write_lockfile() {
    import os
    import time

    path = d.getVar('QNX_SDP_LOCKFILE')
    if not path:
        bb.fatal("set QNX_SDP_LOCKFILE to the file to write")

    installed = qnx_sdp_installed(d)
    if not installed:
        bb.fatal("nothing installed to record; is QNX_SDP_ROOT correct?")

    bb.utils.mkdirhier(os.path.dirname(path))
    with open(path, 'w') as f:
        f.write("# QNX SDP lockfile -- generated by 'bitbake -c write_lockfile "
                "qnx-sdp' on %s\n" % time.strftime('%Y-%m-%d'))
        f.write("# Resolved from QNX_SDP_FEATURES; edit those, not this.\n")
        for pkg in sorted(installed):
            f.write('%s/%s\n' % (pkg, installed[pkg]))

    bb.plain("wrote %d packages to %s" % (len(installed), path))
}
addtask write_lockfile
do_write_lockfile[nostamp] = "1"
do_write_lockfile[doc] = "Record the installed packages as the lockfile"


# ---------------------------------------------------------------------------
# search -- what packages exist?
# ---------------------------------------------------------------------------
python do_search() {
    import os
    import re

    pattern = d.getVar('QNX_SDP_SEARCH') or ''

    out = qnx_sdp_run(d, ['-list',
                          '-listFormat', '${id}|${version}|${org.eclipse.equinox.p2.name}',
                          '-destination', d.getVar('QNX_SDP_ROOT')],
                      'searching the catalogue')

    rows = []
    for line in out.splitlines():
        if not line.startswith('com.qnx.'):
            continue
        parts = line.split('|')
        if len(parts) < 3:
            continue
        pkg, version, name = parts[0], parts[1], '|'.join(parts[2:])
        if pattern and pattern.lower() not in line.lower():
            continue
        rows.append((pkg, version, name))

    if not rows:
        bb.plain("nothing matched '%s'" % pattern)
        return

    # Latest version of each id only, otherwise every package appears several times.
    latest = {}
    for pkg, version, name in rows:
        if pkg not in latest or version > latest[pkg][0]:
            latest[pkg] = (version, name)

    installed = qnx_sdp_installed(d)
    bb.plain("%-62s %-9s %s" % ('PACKAGE', 'STATUS', 'NAME'))
    for pkg in sorted(latest):
        version, name = latest[pkg]
        bb.plain("%-62s %-9s %s"
                 % (pkg, 'installed' if pkg in installed else '-', name.strip()))
    bb.plain("\n%d package(s). Filter with QNX_SDP_SEARCH, e.g.\n"
             "  bitbake -c search qnx-sdp -R <(echo 'QNX_SDP_SEARCH = \"screen\"')"
             % len(latest))
}
addtask search
do_search[nostamp] = "1"
do_search[doc] = "List packages available from the QNX repository"



# ---------------------------------------------------------------------------
# resolve -- what would be installed, and would it work?
# ---------------------------------------------------------------------------
python do_resolve_sdp() {
    selected = qnx_sdp_selected_packages(d)
    if not selected:
        bb.fatal("nothing selected. Set QNX_SDP_FEATURES (and provide a "
                 "lockfile), or QNX_SDP_EXTRA_PACKAGES.")

    bb.plain("%d package(s) selected by features [%s]:"
             % (len(selected), d.getVar('QNX_SDP_FEATURES') or ''))
    for pkg, version in selected.items():
        bb.plain("  %s%s" % (pkg, '/' + version if version else ''))

    installed = qnx_sdp_installed(d)
    to_add = [p for p in selected if p not in installed]
    bb.plain("\n%d already installed, %d would be added"
             % (len(selected) - len(to_add), len(to_add)))

    if to_add:
        ius = ','.join('%s%s' % (p, '/' + selected[p] if selected[p] else '')
                       for p in to_add)
        bb.plain("\nverifying the combination is satisfiable ...")
        out = qnx_sdp_run(d, ['-verifyOnly', '-installIU', ius,
                              '-destination', d.getVar('QNX_SDP_ROOT')],
                          'verifying')
        bb.plain(out.strip() or '(no output)')
}
addtask resolve_sdp
do_resolve_sdp[nostamp] = "1"
do_resolve_sdp[doc] = "Show what QNX_SDP_FEATURES resolves to, and dry-run it"


# ---------------------------------------------------------------------------
# install_sdp -- actually change the SDP
# ---------------------------------------------------------------------------
# Deliberately never a dependency of anything. It needs the network and
# credentials, it mutates a shared multi-gigabyte tree that other builds and
# possibly other checkouts are using, and the SDP is licensed so its contents
# must not travel through an sstate mirror.
python do_install_sdp() {
    import os

    selected = qnx_sdp_selected_packages(d)
    if not selected:
        bb.fatal("nothing selected; run -c resolve_sdp to see why")

    sdp = d.getVar('QNX_SDP_ROOT')
    credentials = d.getVar('QNX_SDP_CREDENTIALS_FILE')
    if not credentials or not os.path.isfile(credentials):
        bb.fatal("QNX_SDP_CREDENTIALS_FILE '%s' not found. Create it outside "
                 "version control with your myQNX login:\n"
                 "  -myqnx.user\n  you@example.com\n  -myqnx.password\n  secret\n"
                 "and chmod 600 it." % credentials)

    ius = ','.join('%s%s' % (p, '/' + selected[p] if selected[p] else '')
                   for p in selected)

    args = ['-url', d.getVar('QNX_QSC_URL'),
            '-destination', sdp,
            '-installIU', ius]

    profile = d.getVar('QNX_QSC_PROFILE')
    if profile:
        args += ['-profile', profile]

    args += (d.getVar('QNX_QSC_EXTRA_ARGS') or '').split()
    args.append('@' + credentials)

    bb.plain("installing %d package(s) into %s" % (len(selected), sdp))
    out = qnx_sdp_run(d, args, 'installing')
    bb.plain(out.strip()[-4000:] or '(no output)')

    bb.plain("\nNow record the result:\n  bitbake -c write_lockfile qnx-sdp")
}
addtask install_sdp
do_install_sdp[nostamp] = "1"
do_install_sdp[network] = "1"
# The credentials path must not enter the task signature.
do_install_sdp[vardepsexclude] += "QNX_SDP_CREDENTIALS_FILE"
do_install_sdp[doc] = "Install the selected packages (needs network + credentials)"

