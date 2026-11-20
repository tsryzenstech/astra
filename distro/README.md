# astraOS Desktop image

The Debian based image of astraOS Desktop (architecture: [docs/DESKTOP.md](../docs/DESKTOP.md)).

```
sudo distro/build.sh iso      out/distro/astraOS-<version>-desktop.iso     live ISO (BIOS + UEFI): recovery and installer
sudo distro/build.sh ota      out/distro/astraOS-<version>-desktop-system.tar.gz + ota.json    the update
sudo distro/build.sh rootfs   out/distro/rootfs                            only the root file system
```

Run it as root on Debian/Ubuntu or WSL2 (debootstrap, squashfs-tools, xorriso, grub-pc-bin, grub-efi-amd64-bin, mtools, rsync;
and to build astra itself `libinput-dev libudev-dev` next to the Qt 6.8.3 SDK).

```
distro/
  build.sh                 astra built for the desktop + the Debian root + squashfs + the ISO / the OTA tarball
  collect-qt.sh            copies the Qt astra was built with (found with ldd) into the image's /system
  packages.list            the Debian packages (drivers, firmware, microcode, Firefox ESR, NetworkManager, ...)
  overlay/                 copied over the root file system
    etc/systemd/system/    astra-bootanim, astra-session (astrad + SysBoard), astra-first-boot, astra-live, astra-ota-apply
    usr/lib/astra/         session.sh, session-prepare.sh, live-setup.sh, first-boot.sh, ota-apply.sh, installer/install.sh
    system/media/bootanimation/desc.txt     the boot animation of the desktop (smaller, held until the shell draws)
    Applications/          Linux programs as apps (Browser.legacy.json)
```

## How it boots

1. UEFI/BIOS → GRUB → Debian's kernel and initramfs → **systemd**. The kernel command line is quiet (`quiet loglevel=0
   systemd.show_status=false ... vt.global_cursor_default=0`): no log line is ever on the screen. `astra.debug` on the command
   line turns the logs and the input debugging back on; `astra.env.NAME=VALUE` sets a variable for the session.
2. `astra-bootanim.service`: the phone's boot animation, smaller, until `/run/astra/shell.ready` (SysBoard drew its first frame).
3. `astra-ota-apply.service`: puts a downloaded update in place.
4. `astra-session.service` (instead of a login manager): `astrad` as root, SysBoard as `astra-system` through KMS (`eglfs_kms`).
   The pointers and touch go through libinput, the keyboard through Qt's evdev plugin (`sysboard/inputbridge.cpp`, `main.cpp`).
5. Live ISO (`astra.live=1`): `astra-live.service` marks the system live, SysBoard starts the **recovery** (Install astraOS,
   Disk Utility, Browser, Terminal; no Activities, no Dock). The installed system starts with the setup wizard.

## The installer and the boot menu

`installer/install.sh` (called by astrad's `installer` service) writes a GPT disk (BIOS boot, EFI, ext4), copies the live
system with `rsync`, and installs GRUB for UEFI and BIOS.

* **Erase the disk**: astraOS alone, GRUB starts it silently (no menu, no timeout).
* **Dual boot** (`--dual`): astraOS goes in a partition the user chose or made in free space; the other systems are not
  touched; `os-prober` finds them and GRUB shows its menu at every start.

## Drivers

Mesa (AMD, Intel, nouveau), Vulkan, `firmware-linux`, `firmware-misc-nonfree`, `firmware-amd-graphics`, `firmware-intel-graphics`,
`firmware-iwlwifi`, `firmware-realtek`, `firmware-atheros`, `firmware-brcm80211`, `firmware-sof-signed` and the AMD/Intel microcode
are in `packages.list`. NVIDIA's proprietary driver is installed by `first-boot.sh` on the installed system. When Qt cannot use
the GPU SysBoard renders in software (llvmpipe). **None of the real-GPU paths has been run on real hardware by the build.**

## Updates

GitHub releases (`OTA_REPOSITORY`, default `tsryzenstech/astra`), each with `ota.json` and
`astraOS-<tag>-desktop-system.tar.gz`; versions as the phone's (`docs/VERSIONING.md`). The workflow that builds them,
`.github/workflows/desktop-iso.yml`, is **deliberately not committed yet**: it goes in when the desktop is done.

## Not done

* Secure Boot; suspend on lid close; the keyboard layout chosen in the setup is not applied to SysBoard (US layout);
* the audio mixer on PipeWire for the desktop;
* multi-user (the shell has one user, the first in `/home`).
