# astraOS Desktop image

The Debian based image of astraOS Desktop (architecture: [docs/DESKTOP.md](../docs/DESKTOP.md)).

> **Status: a scaffold. None of this has been run to the end, and no image has been booted.** The astra part (SysBoard,
> astrad, the apps) runs on a desktop Linux in a window (`scripts/dev-desktop.sh`, verified headless). What is
> written here is what turns it into a system you boot: the Debian root, the systemd units, the update. Expect to fix
> things on the first real build and the first real boot, and test on a spare machine or a VM with a GPU first.

```
distro/
  build.sh                 builds the root file system (mmdebstrap), installs astra, writes the .img (GPT, ESP + ext4, GRUB)
  packages.list            the Debian packages
  overlay/                 copied over the root file system
    etc/systemd/system/    astra-bootanim, astra-session (astrad + SysBoard), astra-ota-apply
    usr/lib/astra/         session.sh, session-prepare.sh, ota-apply.sh
```

## How it boots

1. UEFI → GRUB → Debian's kernel and initramfs → **systemd** (PID 1; astra's own init is the phone's).
2. `astra-bootanim.service` shows the same boot animation as the phone as soon as the display driver is there.
3. `astra-ota-apply.service`: when astrad downloaded an update, puts the new `/system` and `/Applications` in place.
4. `astra-session.service` (on `graphical.target`, on tty1, instead of a login manager): `session.sh` starts `astrad` as
   root and SysBoard as the `astra-system` user with the groups `video render input audio media_rw`. SysBoard
   draws on the display through KMS (`eglfs_kms`, as on the phone), takes the boot animation's place and shows the
   lock screen. The first start shows the setup, full screen.
5. Network: NetworkManager (astrad's network service talks to iwd and BlueZ on the phone; the desktop's one on top of
   NetworkManager is **not written yet**: Wi-Fi in the setup and in Settings needs it, see "Not done").

## Drivers

Mesa (AMD, Intel, nouveau) and the Vulkan drivers are in `packages.list`. NVIDIA's proprietary driver is
installed from Debian's `non-free` (`nvidia-driver`) by a first-boot step that is **not written yet**. A GPU Qt cannot use
makes SysBoard fall back to software rendering (`llvmpipe`), as it does on the phone when there is no GPU, and that is
not smooth: the "smooth from the first frame" goal needs a real test on real GPUs.

## Updates

Like the phone: GitHub releases of the image's repository (`OTA_REPOSITORY`, default `tsryzenstech/astra_desktop`: **that
repository has to be created**), each with `ota.json` and `astraOS-<tag>-desktop-system.tar.gz`:

```json
{ "format": 1, "device": "desktop", "tag": "27.1.3-rev1", "version": "27.1.3-rev1", "codename": "Candyland",
  "channel": "prerelease", "time": 1762531200, "notes": ["..."],
  "files": { "system": { "name": "astraOS-27.1.3-rev1-desktop-system.tar.gz", "size": 0, "sha256": "...",
                         "raw_size": 0, "raw_sha256": "..." } } }
```

`astrad`'s update service (`updateservice.cpp`) handles both: on a desktop its one file is `system` (a tar of `system/` and
`Applications/`), unpacked to `/data/ota/apply/system.tar` and checked; "Install and restart" runs `systemctl reboot`.
Pre-release and release channels are the build's, as on the phone (`docs/VERSIONING.md`). The kernel, firmware and
drivers are Debian's and update with `apt`.

## Not done

* the build and the boot (see the top);
* the NetworkManager backend of astrad's network service, the audio mixer on PipeWire for the desktop, brightness and
  battery on a laptop (`hardwareservice` reads the phone's sysfs paths), suspend on lid close;
* NVIDIA's driver; Secure Boot; an installer that writes the image to a disk (today: write the `.img` to a USB stick);
* the GitHub Actions workflow that builds the image and publishes the OTA release (it goes with the repository above);
* multi-user: the Mac-like `/Users`, but the shell has one user (the first in `/home`).
