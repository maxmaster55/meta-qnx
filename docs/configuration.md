# Configuration

Where every setting lives, and which ones have to agree with each other.

The second half is the important one. Most of what has gone wrong with these
images has not been a wrong value — it has been *two* values that were supposed
to be the same and quietly were not.

## Contents

- [The three places a setting can live](#the-three-places-a-setting-can-live)
- [Site settings: `local.conf`](#site-settings-localconf)
- [Project settings: the image recipes](#project-settings-the-image-recipes)
- [Values that must agree](#values-that-must-agree)
- [Worked example: changing the panel](#worked-example-changing-the-panel)
- [Symptom to cause](#symptom-to-cause)

## The three places a setting can live

| Where | For | Example |
| --- | --- | --- |
| `build-qnx/conf/local.conf` | Things about *your machine or your network* | `QNX_SDP_ROOT`, the wifi credentials file |
| A layer's recipe or `conf/*.inc` | Things about *this project* that more than one file needs | guest and host IP addresses, the vdev addresses |
| Inline in a `.build.in` template | Things about *this board* that nothing else reads | the SPI base address, the SDIO controller address |

The rule for the middle row, and the reason `conf/qnx-guest-vdevs.inc` exists:

> **A value becomes a variable when more than one file has to agree on it.**

Not because it might be tuned one day — that is what a comment is for. Lifting a
value that appears once into a variable adds a layer of indirection and removes
no way to be wrong. Lifting one that appears twice removes the only way it can be
wrong, which is the two copies disagreeing.

## Site settings: `local.conf`

Created from `meta-qnx/conf/templates/default/local.conf.sample`. Everything has
a default except the first.

| Variable | Default | What it does |
| --- | --- | --- |
| `QNX_SDP_ROOT` | `${TOPDIR}/qnx-sdp` | The QNX SDP. Read-only except for `bitbake -c install_sdp qnx-sdp`. |
| `QNX_PROJECT_SRC` | unset | A working tree of application sources, for recipes built in place. Recipes needing it are skipped cleanly when unset. |
| `QNX_HOST_CONF_WIFI` | unset | Path to a real `wpa_supplicant.conf`. Left unset, a placeholder ships and the board will not join a network — the build warns. |
| `QNX_QSC_CLT` | unset | QNX Software Center CLI, for managing SDP packages. See [sdp.md](sdp.md). |
| `QNX_SDP_FEATURES` | see `qnx-sdp-features.inc` | Which package sets the SDP should contain. |

`QNX_HOST_CONF_WIFI` points at a file holding a network passphrase, so keep it
outside the repository:

```bash
wpa_passphrase "your-ssid" "your-passphrase" > ~/wpa_supplicant.conf
```

Delete the commented `#psk="..."` plaintext line it leaves behind; the hashed
`psk=` below it is what gets used. Either way the result ends up readable in the
IFS by anyone holding the SD card.

That output is a network block and nothing else, which is not a usable
supplicant configuration on its own — it has no `ctrl_interface`, so
wpa_supplicant creates no control socket and `wpa_cli` cannot attach to ask
whether it associated. The recipe prepends the globals QNX's own reference uses
(`QNX_HOST_CONF_WIFI_GLOBALS`) unless your file already sets `ctrl_interface`,
in which case it is taken exactly as written.

## Project settings: the image recipes

These are `?=`, so `local.conf` overrides any of them.

### Host — `meta-qnx-hyp/recipes-image/qnx-host-image/qnx-host-image_1.0.bb`

| Variable | Default | Notes |
| --- | --- | --- |
| `QNX_HOST_BRIDGE_IP` | `192.168.2.2` | The board's address on the LAN. Static, not DHCP: the board is the gateway for two guest networks and a changing lease would break their routing silently. |
| `QNX_HOST_BRIDGE_MASK` | `255.255.255.0` | |
| `QNX_HOST_GATEWAY` | `192.168.2.1` | Must be on the bridge's subnet. |
| `QNX_HOST_GUEST_IP` / `_NET` | `10.0.0.1` / `10.0.0.0/24` | The host's end of the QNX guest link, and the network NAT'd out through the bridge. |
| `QNX_HOST_LINUX_IP` / `_NET` | `10.0.1.1` / `10.0.1.0/24` | Same for the Linux guest. A different subnet on purpose — both are point-to-point links to this host, and one `/24` would make the routing table ambiguous. |
| `QNX_HOST_GUEST_PEER` / `_LINUX_PEER` | `/dev/qvm/guest_N/guest_to_host` | `/dev/qvm/<system>/<vdev name>`, taken from the guest's `.qvmconf`. Disagree and `vpctl` binds nothing and the guest comes up with a dead interface. |
| `QNX_HOST_SDMMC_ADDR` / `_IRQ` | `0x1000fff000` / `305` | The SD card controller. **Not** the wifi radio's — see below. |

### Guest — `meta-qnx-guest/conf/qnx-guest-vdevs.inc`

Required by both the guest image recipe *and* the `qnx-host-data` bbappend that
writes the `.qvmconf`, which is the whole point: one file, both consumers.

| Variable | Default | Also read by |
| --- | --- | --- |
| `QNX_GUEST_RAM` | `0x80000000,2G` | — |
| `QNX_GUEST_CONSOLE_LOC` / `_INTR` | `0x20000000` / `42` | the guest's `devc-virtio` line |
| `QNX_GUEST_ROOTFS_LOC` / `_INTR` | `0x1c0b0000` / `45` | `.rootfs-mount.sh` (`devb-virtio smem=,irq=`) |
| `QNX_GUEST_GPU_LOC` / `_INTR` | `0x1c0e0000` / `39` | `graphics-virtio-start.sh`, **in the qnx-host-conf repo** |
| `QNX_GUEST_SCANOUT_WIDTH` / `_HEIGHT` | `1024` / `600` | two `.conf` files, **in the qnx-host-conf repo** |
| `QNX_GUEST_SCANOUT_DISPLAY` | `1` | `graphics-host-rpi5.conf`, same repo |

Guest IPs live in `qnx-guest-image_1.0.bb`: `QNX_GUEST_IP` (`10.0.0.2`) and
`QNX_GUEST_GATEWAY` (`10.0.0.1`, which is the host's `QNX_HOST_GUEST_IP`).

Addresses that appear **only** in `qnx-guest.qvmconf` — the pl011, the shmem
region, the watchdog, the entropy source, the guest-to-guest link — are written
out there as literals, with the interrupt map at the top of the file as their
documentation. There is nothing for them to disagree with.

### Board data, inline in the templates

Not variables, because nothing outside one file reads them. All in
`meta-qnx-hyp/recipes-image/qnx-host-image/files/qnx-host.build.in`:

- `/etc/system/config/spi/spi.conf` — SPI0 at `0x1f00050000`, IRQ 179
- `/etc/qwdi_wifi.conf` — the radio's SDIO controller at `0x1001100000`, IRQ 306
- `/etc/io-sock.conf` — `hw.dhdsdio.dev0="rpi5"`, and where the driver finds the above

Note that the wifi radio and the SD card are on **different SDIO controllers**.
`0x1000fff000`/305 is the card; `0x1001100000`/306 is the radio. Both values came
from the SDP's own RPi5 definition, in
`host/common/mkqnximage/extras/rasppi/rpi5/opt_scripts/rasppi5` — which is the
reference to check against when something board-level does not come up.

## Values that must agree

Nothing in the build verifies any of these. Each row is a way to produce an image
that builds cleanly and does not work.

| Value | Places | If they disagree |
| --- | --- | --- |
| **Panel size** | 4: `QNX_GUEST_SCANOUT_*`; guest `graphics-virtio-mmio.conf` `video-mode`; host `graphics-host-rpi5.conf` display 1 `video-mode`; the physical panel | The vdev scans out 1:1 with no scaling, so the guest appears in a corner of the display or cropped — which reads as a broken application, not a wrong number |
| **GPU address** | 2: `QNX_GUEST_GPU_LOC`/`_INTR`; `graphics-virtio-start.sh` | `drm-virtio` binds nothing, `/dev/dri/card0` never appears, no Screen, no cluster, and no message naming the cause |
| **Data disk address** | 2: `QNX_GUEST_ROOTFS_LOC`/`_INTR`; `.rootfs-mount.sh` | `/dev/vblk0` never appears; the guest boots with no Qt and no graphics stack |
| **Console address** | 2: `QNX_GUEST_CONSOLE_LOC`/`_INTR`; the `.qvmconf` | No guest console output at all |
| **vdevpeer path** | 2: `QNX_HOST_GUEST_PEER`; the guest's `.qvmconf` `system` + vdev `name` | `vpctl` binds nothing; the guest's interface exists and carries no traffic |
| **Guest gateway** | 2: `QNX_GUEST_GATEWAY`; `QNX_HOST_GUEST_IP` | The guest routes to an address nothing answers on |
| **Interrupt numbers** | all of `qnx-guest.qvmconf` | Two vdevs on one interrupt is not an error qvm reports. Keep the map at the top of that file current |

The first four are single-sourced on *this* side. The other halves of rows 1 and
2 live in the **qnx-host-conf** repository, and nothing here can check them —
changing a panel or a GPU address means editing that repository too.

## Worked example: changing the panel

Say the panel becomes 1280x800. Four edits:

1. `meta-qnx-guest/conf/qnx-guest-vdevs.inc`

   ```bitbake
   QNX_GUEST_SCANOUT_WIDTH ?= "1280"
   QNX_GUEST_SCANOUT_HEIGHT ?= "800"
   ```

   or, without touching the layer, in `local.conf`:

   ```bitbake
   QNX_GUEST_SCANOUT_WIDTH = "1280"
   QNX_GUEST_SCANOUT_HEIGHT = "800"
   ```

2. In the **qnx-host-conf** repo, `display/graphics-host-rpi5.conf`:

   ```
   begin display 1
     video-mode = 1280 x 800 @ 60
   ```

3. In the same repo, `display/graphics-virtio-mmio.conf`, the guest's own
   `video-mode`, to the same numbers.

4. Re-pin `QNX_SRC_REV` in `qnx-host-conf_1.0.bb` and `qnx-guest-conf_1.0.bb` to
   the new commit, unless you are on `AUTOREV`.

Then `bitbake qnx-host-disk`. Skipping step 2 or 3 gives you an image that boots
and shows the cluster in the top-left corner of a mostly black screen.

## Symptom to cause

| On the console | Look at |
| --- | --- |
| `Unable to access "/dev/io-spi" (2)` | `spi.conf` has no `[dev]` section — the bus comes up and publishes no device |
| `Couldn't open libGLESv2.so.2` | The compatibility symlink in `qnx-screen_1.0.bb`. `libepoxy` `dlopen`s that name, so the DT_NEEDED closure cannot see it |
| `wifi: the driver attached but the radio did not come up` | `sdio_baseaddr` / `sdio_irq` in `/etc/qwdi_wifi.conf` |
| `Failed to connect to non-global ctrl_ifname: bcm0` | No `ctrl_interface=` in `wpa_supplicant.conf`, so the supplicant made no control socket. It is running; you just cannot ask it anything. `wpa_passphrase` output alone does this — the recipe now adds the globals |
| `ERROR: /dev/screen did not appear` | `graphics-host-rpi5.conf`, and that the panel is on the HDMI port that config calls display 1 |
| `ERROR: data disk did not mount` | `QNX_GUEST_ROOTFS_LOC`/`_INTR` against the `.qvmconf` |
| Guest boots, panel stays black | Whether the `.qvmconf` still has its `vdev virtio-gpu`, and whether host Screen was up *before* qvm started |
| `Entry '<path>' redefined` at build time | Two recipes claiming one path. See [where-things-come-from.md](where-things-come-from.md) |
| Guest dies at launch with no message | Host Screen was not up. `customize_startup.sh` must run in the foreground, before the guest |

## See also

- [variables.md](variables.md) — every variable the layer defines
- [adding-a-recipe.md](adding-a-recipe.md) — getting new software into an image
- [sdp.md](sdp.md) — choosing and installing SDP packages
