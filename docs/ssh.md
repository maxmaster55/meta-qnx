# ssh: host keys, user keys, and why a password was refused

Three separate things are called "the ssh key" on these boards, and they fail in
different ways. This is what each one is and where it lives.

## 1. The board's own identity (host keys)

The **host's** key is generated on the board, not shipped: a key baked into an
image is the same key on every board written from it, so it would prove nothing
about which board you reached.

The **guests'** keys go the other way — generated at build time by the
`ssh-hostkeys` recipe and shipped, so the host can pre-accept them. See
[§4](#4-pre-accepted-guest-keys) for why the opposite answer is right there.

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

`/.ssh` is `~/.ssh` there, and it is one key installed once and linked, not two
files — two copies of a key can drift apart.

Measured on the board rather than assumed, because the explanation that used to
be here was wrong twice over. It claimed `/etc/passwd` gives root `/home/root`
(it gives `/root`) and that `HOME=/` comes from `/etc/profile` (which, when that
was written, nothing read — `ENV` was set nowhere, so the file was inert). What
is actually true:

```
$ grep ^root: /etc/passwd | cut -d: -f6      ->  /root
$ sh -c 'echo $HOME'                          ->  /       (non-interactive)
$ ksh -i -c 'echo $HOME'                      ->  /       (interactive)
$ ls -l /.ssh/id_ed25519                      ->  -> /root/.ssh/id_ed25519
```

`HOME` is `/` for both kinds of shell, so `~/.ssh` resolves to `/.ssh` whoever
asks. But do not lean on that: the reason both of `hms.conf`'s paths work is
the **symlink**, which is there whatever `HOME` happens to be.

### The variables

| Variable | Where | What |
| --- | --- | --- |
| `QNX_SSH_AUTHORIZED_KEYS` | image | public key lines; baked into the IFS as a SEED only -- see [§3a](#3a-why-authorized_keys-had-to-move-too) |
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
`meta-qnx-hyp/conf/hms-ssh-key.inc`. The private half is never in this tree —
it is named by path:

```bitbake
# build-qnx/conf/local.conf
QNX_SSH_IDENTITY = "/path/to/hms_ssh_key"
```

The pair in use was generated locally, into the gitignored build directory.
The reference project's pair could not be reused: its private half exists only
*inside* the images it ships, because the source path its build file reads is
gitignored there, so the monorepo carries the `.pub` and nothing else.

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

### 3a. Why authorized_keys had to move too

The point of `QNX_SSH_AUTHORIZED_KEYS` was never to be the only way in forever
— an operator running `ssh-copy-id` from their own machine should just work,
the same as on any other box. It did not:

```
$ ssh-copy-id root@10.0.0.2
... key added, but every subsequent login still asks for a password
```

`ssh-copy-id` does not talk to sshd or read `sshd_config`. It connects, then
appends to `~/.ssh/authorized_keys` over that connection. Two things had to
both be true for that append to actually take effect, and neither was:

1. **`sshd` was reading a different file than the one being appended to.**
   `AuthorizedKeysFile` defaulted to `.ssh/authorized_keys`, resolved against
   `/root` (from `/etc/passwd`, not `$HOME`) — i.e. `/root/.ssh/authorized_keys`,
   the file `QNX_SSH_AUTHORIZED_KEYS` bakes into the IFS. Now points at
   `${QNX_SSH_KEYDIR}/authorized_keys` on the data partition instead — the same
   directory the host keys and `known_hosts` already live in, for the same
   reason: `/root/.ssh` is read-only and RAM-resident, so nothing appended
   there was ever going to survive a reboot, or even the append itself.

2. **The path `ssh-copy-id` actually writes to was inside the read-only IFS as
   well.** `HOME` is `/` here (§3, above), so `~/.ssh/authorized_keys` is
   `/.ssh/authorized_keys` — not `/root/.ssh/authorized_keys`, a different path
   entirely, and one nothing used to touch. `qnx-ssh` now ships
   `[type=link] /.ssh/authorized_keys = ${QNX_SSH_KEYDIR}/authorized_keys`, the
   same trick already used for `/.ssh/id_ed25519` on the host: the symlink
   itself is baked into the read-only IFS, but opening *through* it for append
   only needs the **target's** directory to be writable, which `/var/ssh` is.

`QNX_SSH_AUTHORIZED_KEYS` still does exactly what it did — it is what a freshly
flashed board can be reached with at all, before anyone has run `ssh-copy-id`
against it. `ssh-server.sh` copies that seed onto the data partition once, the
same "generate/seed only if not already there" idiom as the host keys just
above it, and from then on the data-partition copy is what's authoritative:
whatever gets appended to it — by `ssh-copy-id`, from any machine, at any point
after first boot — persists, because sshd is reading that copy and nothing ever
overwrites it again.

Guest-2 (Linux, dropbear) is not this component and is not affected by any of
this — see "The Linux guest is different" above. `ssh-copy-id` against it still
depends on whatever `hms-ssh-key` in `meta-bmo` already does.

## 4. Pre-accepted guest keys

Host-to-guest ssh used to be unverifiable, and `hms` papered over it with
`StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` — accept whatever
answers, then throw away the evidence. That was not carelessness: the guests had
no writable `/var/ssh`, so they minted a new identity on every boot and real
checking was impossible.

The `ssh-hostkeys` recipe in meta-qnx-hyp closes it. At build time it generates
one ed25519 host key per guest and a matching `known_hosts`:

```
guest-1/ssh_host_ed25519_key      → guest rootfs, /var/ssh/
known_hosts                       → host data partition, /var/ssh/known_hosts
```

`ssh-server.sh` only generates a key when it does not find one, so the guest
keeps the shipped identity from its first boot — and the host already has it
before the guest has ever run. No prompt, no TOFU window, and `hms` now uses
`StrictHostKeyChecking=accept-new` rather than `no`.

### Why baking keys in is right here and wrong for the host

| | host key | guest keys |
| --- | --- | --- |
| reached by | a person, from a laptop, over the LAN | `hms` only, from the host it runs on |
| over | a real network | a point-to-point virtual wire inside one board |
| can anything else answer? | yes | no — `10.0.0.2` has no route off the board |
| so | generate per board | generate per build |

### guest-2 is different

The Linux guest runs dropbear, whose host keys are in dropbear's own format, and
converting an OpenSSH key needs `dropbearconvert` — which this build has no
native recipe for. Putting it in `known_hosts` anyway would be worse than leaving
it out: the host would hold a key the guest does not have, turning a first-
connection prompt into a hard mismatch. It is pinned on first contact by
`accept-new` instead.

### Regenerating

The keys are stable across rebuilds because `do_compile` is cached in sstate.

```bash
bitbake -c cleansstate ssh-hostkeys
```

mints new ones — after which **both images must be rebuilt together**, or the
host's `known_hosts` names a key the guest no longer has and every connection
fails closed.

### Outbound known_hosts

`/root/.ssh` is in the read-only IFS, so the ssh *client* could never record a
host key there:

```
Failed to add the host to the list of known hosts (/root/.ssh/known_hosts)
```

Both images now ship an `ssh_config` pointing `UserKnownHostsFile` at
`${QNX_SSH_KEYDIR}/known_hosts` on the data partition, which is the same file the
pre-accepted guest keys live in and where runtime-learned entries accumulate.

## 5. Things that were installed but never started

Three faults found on hardware, all the same shape — the binary was in the image
and nothing ran it, so the symptom pointed somewhere else entirely.

| symptom | actual cause |
| --- | --- |
| `ssh root@10.0.0.2` → connection timed out | the guest's virtio-net vdevs were declared in the order that puts the host link on `vtnet1`, so `10.0.0.2` sat on the guest-to-guest wire |
| `Connection refused` once ping worked | the guest installed `qnx-ssh` but never ran `.ssh-server.sh` |
| `PTY allocation request failed on channel 0` | the guest had `devc-pty` and never started it, so sshd could authenticate but not allocate a terminal |

The vdev one is worth remembering: the guest enumerates virtio-net vdevs in
**reverse declaration order**, so the one declared *last* becomes `vtnet0`. The
MMIO addresses are identical whichever way round they are written, so they look
like they settle the question and do not. The MACs are what give it away — the
`mac` line on `guest_to_host` appears on whichever interface it really is.
