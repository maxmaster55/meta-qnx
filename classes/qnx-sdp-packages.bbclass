# qnx-sdp-packages.bbclass -- describe, verify and install the SDP's contents.
#
# The SDP is not built here; it is installed by qnxsoftwarecenter_clt from QNX's
# servers. What this class provides is a way to say *what* should be in it, to
# check that it is, and to make it so.
#
# The split follows package.json / package-lock.json:
#
#   QNX_SDP_FEATURES   intent. Readable, unpinned, checked into the project.
#   the lockfile       the resolved result: exact package ids and versions,
#                      generated from an installed SDP rather than written.
#
# You never hand-write a version. p2 (the Eclipse provisioning engine
# qnxsoftwarecenter_clt wraps) resolves dependencies, -verifyOnly proves a
# combination is satisfiable before anything is touched, and the snapshot records
# what it actually chose. Two machines with the same lockfile get the same SDP;
# regenerating it is a reviewable diff.
#
# Features are namespace patterns rather than lists of ids, because an SDP has
# hundreds of packages (qnx800 alone has ~540) and its namespaces are already
# meaningful -- target.net, target.screen, target.utils and so on. A pattern also
# survives QNX reorganising a namespace's contents.

# ---------------------------------------------------------------------------
# Where the tools live
# ---------------------------------------------------------------------------
# The QNX Software Center's command-line tool. Not part of the SDP: it is what
# installs the SDP, so it is found separately.
QNX_QSC_CLT ?= ""

# The repository it talks to.
QNX_QSC_URL ?= "https://www.qnx.com/swcenter"

# Extra arguments passed to every install. The defaults mirror what QNX BSP
# build systems use: allow experimental packages, and prefer leaving existing
# packages alone over upgrading them.
QNX_QSC_EXTRA_ARGS ?= "-setExperimentalEnabled=true -setPolicy=conservative"

# p2 profile identifying this installation. qnxsoftwarecenter_clt derives one
# per SDP directory automatically, so leaving this empty is normal; set it only
# when several checkouts on one machine must not share a profile.
QNX_QSC_PROFILE ?= ""

# Credentials. NEVER put these in a layer or a recipe: point at a file outside
# version control holding the myQNX arguments, in the same @file form the SDP's
# own tooling uses:
#
#     -myqnx.user
#     you@example.com
#     -myqnx.password
#     secret
#
# The path is excluded from task signatures and never echoed.
QNX_SDP_CREDENTIALS_FILE ?= "${@os.path.join(os.environ.get('HOME', '/root'), '.qnx', 'qsc-credentials')}"

# ---------------------------------------------------------------------------
# What should be installed
# ---------------------------------------------------------------------------
# Package id prefix, derived from the SDP version so nothing hardcodes 8.0.
QNX_SDP_VERSION ?= "qnx800"
QNX_SDP_PKG_PREFIX ?= "com.qnx.${QNX_SDP_VERSION}"

# Feature names to install. Definitions come from conf/qnx-sdp-features.inc,
# and a project may add its own with QNX_SDP_FEATURE[name] = "patterns".
QNX_SDP_FEATURES ?= ""

# The resolved snapshot: one "<id>/<version>" per line, exactly the format
# `qnxsoftwarecenter_clt -listInstalledRoots` prints and the format QNX's own
# package list files use, so an existing list can be adopted unchanged.
QNX_SDP_LOCKFILE ?= ""

# Extra package ids to install regardless of features, and ids to keep out.
QNX_SDP_EXTRA_PACKAGES ?= ""
QNX_SDP_EXCLUDE_PACKAGES ?= ""

# Substring filter for `bitbake -c search qnx-sdp`. Empty lists everything.
QNX_SDP_SEARCH ?= ""

# Packages a recipe or image needs. Checked by do_check_sdp, so a missing one is
# named up front rather than surfacing as a mkifs "Host file 'x' not available".
QNX_SDP_REQUIRES ?= ""

QNX_SDP_FEATURE[dummy] ?= ""


def qnx_sdp_varflags(d, varname):
    """Varflags of varname, minus bitbake's own bookkeeping.

    Deliberately a local copy rather than the one in qnx-sdp.bbclass: this class
    must not inherit that one, because it refuses to parse when the SDP is
    missing -- which is precisely when do_install_sdp is needed."""
    flags = d.getVarFlags(varname) or {}
    return {k: v for k, v in flags.items()
            if not k.startswith('_') and k not in ('doc', 'export', 'dummy',
                                                   'vardeps', 'vardepsexclude',
                                                   'vardepvalue')}


def qnx_sdp_feature_patterns(d):
    """Feature name -> list of id patterns, with the version prefix applied."""
    prefix = d.getVar('QNX_SDP_PKG_PREFIX')
    flags = qnx_sdp_varflags(d, 'QNX_SDP_FEATURE')

    out = {}
    for name, value in flags.items():
        patterns = []
        for pattern in (value or '').split():
            # A pattern is relative to the SDP prefix unless it already spells
            # out a full id, so features stay portable across SDP versions.
            if not pattern.startswith('com.qnx.'):
                pattern = '%s.%s' % (prefix, pattern)
            patterns.append(pattern)
        out[name] = patterns
    return out


def qnx_sdp_read_lockfile(d, path=None):
    """Parse a lockfile into {id: version}.

    Accepts both formats the tooling emits: '<id>/<version>' from
    -listInstalledRoots, and '<id>=<version>' from -list."""
    import os

    path = path or d.getVar('QNX_SDP_LOCKFILE')
    if not path or not os.path.isfile(path):
        return {}

    packages = {}
    with open(path) as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line or not line.startswith('com.qnx.'):
                continue
            for separator in ('/', '='):
                if separator in line:
                    pkg, version = line.split(separator, 1)
                    packages[pkg.strip()] = version.strip()
                    break
            else:
                packages[line] = ''
    return packages


def qnx_sdp_selected_packages(d):
    """Resolve QNX_SDP_FEATURES against the lockfile into concrete ids.

    Patterns are matched against the lockfile's ids, which is what keeps
    versions pinned: a feature says "everything under target.net", the lockfile
    says which packages that was and at what version when it was last resolved.
    """
    import fnmatch

    locked = qnx_sdp_read_lockfile(d)
    patterns = qnx_sdp_feature_patterns(d)
    wanted = (d.getVar('QNX_SDP_FEATURES') or '').split()
    excluded = (d.getVar('QNX_SDP_EXCLUDE_PACKAGES') or '').split()

    unknown = [f for f in wanted if f not in patterns]
    if unknown:
        bb.fatal("unknown QNX_SDP_FEATURES: %s. Defined features: %s"
                 % (' '.join(unknown), ' '.join(sorted(patterns)) or '(none)'))

    selected = set()
    for feature in wanted:
        found = set()
        for pattern in patterns[feature]:
            matched = fnmatch.filter(locked.keys(), pattern)
            if not matched:
                # Normal: a feature spans several namespaces and an SDP need not
                # carry all of them (host.win.* on a Linux install, say). Only
                # worth reporting if the whole feature came up empty.
                bb.debug(1, "QNX_SDP_FEATURE[%s]: '%s' matched nothing"
                         % (feature, pattern))
            found.update(matched)

        if not found and locked:
            bb.warn("QNX_SDP_FEATURE[%s] matched no package in the lockfile. "
                    "Its patterns are: %s"
                    % (feature, ' '.join(patterns[feature])))
        selected.update(found)

    selected.update(p for p in (d.getVar('QNX_SDP_EXTRA_PACKAGES') or '').split())

    for pattern in excluded:
        selected.difference_update(fnmatch.filter(selected, pattern))

    return {pkg: locked.get(pkg, '') for pkg in sorted(selected)}
