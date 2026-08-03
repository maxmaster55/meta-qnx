# ssh: host keys, user keys, and why a password was refused

Three separate things are called "the ssh key" on these boards, and they fail in
different ways. This is what each one is and where it lives.

## 1. The board's own identity (host keys)

Generated on the board, not shipped. A key baked into an image is the same key
on every board written from it.

`ssh-server.sh` makes them once and reuses them after, in **`QNX_SSH_KEYDIR`**
(`/var/ssh`), which is on the data partition. They used to land in `/dev/shmem`,
which is RAM, so every boot produced a new identity and every connection said:

```
@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@
```

routinely — which is the one thing that warning must never become.

The fix is a wait, not a path. The boot script starts sshd about sixty lines
before it mounts the data partition, so at key-generation time nothing writable
that outlives a reboot exists yet. The script polls for `QNX_SSH_KEYDIR` for up
to `QNX_SSH_KEYDIR_WAIT` seconds first. That costs nothing — the boot script
backgrounds it, and nothing else waits on sshd.

A board whose data partition never appears still gets ssh, with ephemeral keys
and a message saying so. Losing remote access to a board whose disk did not
mount takes away the tool you would use to find out why.

> After flashing a card for the first time the fingerprint changes once, because
> `/var/ssh` starts empty. `ssh-keygen -R <board>` once, then it stays put.

## 2. Logging in with a password

`UsePAM yes` and `/etc/pam.d/sshd`, both from the `qnx-ssh` component. Neither is
optional, and without them every login is refused **with the correct password**,
indistinguishably from a wrong one:

```
root@192.168.2.2's password:
Permission denied, please try again.
```

The cause is the hash format. QNX writes `/etc/shadow` entries as

```
root:@S@<base64 hash>@<base64 salt>:...
```

and `@S@` is QNX's own format, not a `crypt(3)` one. Exactly one thing in the SDP
can verify it:

```
$ strings pam_qnx.so.2 | grep -c @S@    ->  1
$ strings sshd         | grep -c @S@    ->  0
$ strings libc.so.6    | grep -c @S@    ->  0
```

OpenSSH defaults to `UsePAM no` — the SDP's own stock `sshd_config` has it
commented at that value — so out of the box sshd checks the password with
`crypt()`, `crypt()` cannot parse `@S@`, and the comparison fails for every
password anyone could type. Turning PAM on routes the check through
`pam_qnx.so`, the only thing that understands what is in the file.

This is also why the reference image cannot have had working root ssh: it ships
neither the `pam.d/sshd` file nor `UsePAM`. Its README documenting `root/root` is
describing the console.

## 3. User keys, and the hms workflow

This is the one with a topology worth drawing. `hms` runs on the QNX host and
reaches two kinds of place — the guests it manages, and the server it fetches OTA
packages from — **with the same key**:

```
                    ┌────────────────────────────────────┐
                    │  QNX host                          │
                    │                                    │
                    │  /root/.ssh/id_ed25519  (private)  │
                    │  /.ssh/id_ed25519  ─── link ───┘   │
                    └───┬────────────────────────┬───────┘
                 ssh    │                        │   scp
        ┌───────────────┴──────┐                 │
        ▼                      ▼                 ▼
  guest-1 (QNX)         guest-2 (Linux)    OTA server
  /root/.ssh/           /home/root/.ssh/   maxmaster@…
    authorized_keys       authorized_keys    ~/.ssh/authorized_keys
```

Two paths on the host because `hms.conf` asks for the key by two names:

| `hms.conf` | used for |
| --- | --- |
| `ssh_key=/root/.ssh/id_ed25519` | reaching the guests |
| `ota_server_key=/.ssh/id_ed25519` | reaching the OTA server |

`/.ssh` is `~/.ssh` there: `qnx-base.build.inc` sets `HOME=/` in `/etc/profile`,
even though `/etc/passwd` gives root `/home/root`. It is one key installed once
and linked, not two files — two copies of a key can drift apart.

### The variables

| Variable | Where | What |
| --- | --- | --- |
| `QNX_SSH_AUTHORIZED_KEYS` | image | public key lines; written to `/root/.ssh/authorized_keys` |
| `QNX_SSH_IDENTITY` | `local.conf` | **path on the build host** to a private key |
| `QNX_SSH_IDENTITY_DEST` | image | where it lands (default `/root/.ssh/id_ed25519`) |
| `QNX_SSH_IDENTITY_LINKS` | image | other paths the same key must answer at |

`QNX_SSH_IDENTITY` is a path rather than the key text because it is a secret: the
key file stays outside the layer, and the value belongs in `local.conf` beside
`QNX_SDP_ROOT`. A path that does not exist fails the build naming the variable,
rather than quietly producing a keyless image. It is also a file-checksum on
`do_generate_buildfile`, so replacing the key rebuilds the image — nothing else
would notice, the file being outside the layer.

They are handled in **`qnx-ifs.bbclass`, not in the `qnx-ssh` component**, and
that is load-bearing: `qnx-ssh` is one recipe shared by every image, so a value
set in an image recipe never reaches its datastore. Putting the records there
produced nothing at all, silently.

> `QNX_SSH_AUTHORIZED_KEYS` is split on key **type** tokens (`ssh-`, `ecdsa-`,
> `sk-…`), not on newlines. bitbake's `+=` joins with a space, so two keys
> appended separately arrive as one line — and `authorized_keys` is one key per
> line, so writing that out gives a file sshd reads as a single malformed entry
> and honours neither key.

### Setting it up

The public key both guests authorise is in
`meta-qnx-hyp/conf/hms-ssh-key.inc`. The private half is **not** in this tree,
and is not in the hypervisor monorepo either — that build file reads it from a
gitignored path, so only `hms_ssh_key.pub` is tracked there. Point at it:

```bitbake
# build-qnx/conf/local.conf
QNX_SSH_IDENTITY = "/path/to/hms_ssh_key"
```

Unset, everything still builds and `hms` still starts — it simply cannot log into
a guest, and reports that per connection rather than at build time.

If the pair is ever regenerated, three places have to change together:

1. `QNX_SSH_IDENTITY` — the new private key
2. `QNX_HMS_PUBKEY` in `meta-qnx-hyp/conf/hms-ssh-key.inc` — the QNX guest
3. `HMS_PUBKEY` in `meta-bmo/recipes-setup/hms-ssh-key/hms-ssh-key.bb` — the
   Linux guest

and the OTA server's own `authorized_keys`, which no build controls.

### The Linux guest is different

`bmo-image-ai` is guest-2 and is Linux, so the QNX mechanism does not reach it.
The `hms-ssh-key` recipe in `meta-bmo` does the same job, with two differences
that matter:

- the file goes to **`/home/root/.ssh/authorized_keys`** — poky gives root
  `/home/root`, and putting it in `/root` is silently ignored
- the server is **dropbear**, not openssh, and dropbear refuses a key file it
  considers loosely permissioned: `0700` on the directory, `0600` on the file

### The second authorised key

`qnx800-guest-1.build` in the reference authorises two keys: `hms@hypervisor` and
a `root@localhost`. Both are carried, to match. Almost nothing is known about the
second — its private half is in neither repository, nothing generates it, and the
string appears in exactly one file. Most likely a key made by hand so a person
could log in without a password, which would explain why guest-1 has it and
guest-2 does not. If it belongs to nobody, deleting it is better than keeping it
out of caution.
