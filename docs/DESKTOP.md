# astraOS Desktop

astraOS Desktop is astraOS for computers: the same system as the phone (SysBoard, astrad, the animation engine,
the design language, the permissions, AstraID, Market) with a shell made for a pointer and a keyboard, on a
Debian base. This document is the architecture and the plan; the last section says what is done, and what is
checked.

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ Apps (.apkg)      desktop apps (target "desktop") │ mobile apps (target "mobile") │
│                   resizable windows               │ in a phone shaped window      │
├──────────────────────────────── Wayland ─────────────────────────────────────┤
│ SysBoard   compositor + DesktopShell: menu bar · Dock · windows · Activities  │
│            lock screen · Control / Notification Center · setup (full screen)  │
├──────────────────────────── /dev/socket/astrad ──────────────────────────────┤
│ astrad     the phone's services + PetalDrop · Phone Linker · AstraID (kind)   │
├───────────────────────────────────────────────────────────────────────────────┤
│ Debian (stable) · systemd · NetworkManager · PipeWire · Mesa + vendor drivers  │
│ Linux kernel (Debian's)                                                       │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Decisions

| | |
|---|---|
| Base | **Debian** (stable; `trixie` when it is the stable one). Its kernel, firmware, Mesa, NVIDIA/AMD/Intel drivers and `apt`. "Legacy" software (everything installed with `apt`, Flatpak, ...) lives where it always lives: `/usr`, `/etc`, `/var`, `/home`. |
| Init | **systemd stays PID 1** on the desktop (hardware on a PC is too varied for astra's own init: udev rules, logind seats, suspend, NetworkManager). astra's init (`core/init`) is the phone's. A unit starts astrad and SysBoard: `distro/systemd/`. |
| Shell | **DesktopShell** (`sysboard/qml/Desktop*.qml`), written for the desktop but made of the same parts as the phone's: the springs of `Astra.Animation`, `Glass`, `BlurLayer`, `Panels` (Control Center, Notification Center), banners, calls, alarms, system dialogs, the lock screens (`LockSlots`). `Host.desktop` picks it in `Main.qml`. |
| Form factor | `ro.astra.form` = `phone` \| `desktop` (build.prop, `-DASTRA_FORM=desktop`), `ASTRA_FORM=desktop` in a development tree; `astra::Form` in libastra. |
| Apps | One runtime (`astra-app`), one format (`.apkg`), one manifest, with a `target` (below). |
| Look | The phone's: Poppins, the radii, the accents, light and dark, motion. The desktop only adds what a pointer needs (hover, window frames, the Dock's magnification). |

## Filesystem

astraOS keeps its own tree where it always has, and the desktop adds the Mac-like places for people:

```
/Applications/<Name>.apkg         every app of the system (desktop and mobile builds), read-only
/system/                          astraOS: bin, lib, framework/qml, etc, fonts, media (as on the phone)
/system/etc/priv-apps.txt         the packages of /Applications that hold system permissions (root-owned)
/data/app, /data/data/<package>   installed apps and their private data (as on the phone)
/data/media/0  ->  /home/<user>   the user's files: Music, Pictures, Documents, Download... (/sdcard too)
/Users  ->  /home                 the Mac-like name
/usr, /etc, /var, /opt, /home     Debian's, untouched
```

A package manager scan reads `/Applications` (`Paths::applications()`); when an app has both builds there, the
desktop build is used. Apps installed from Market go to `/data/app`, as on the phone. The image's `/system` and
`/Applications` are updated by the OTA (below), never by `apt`.

## Two kinds of apps: `target`

`app.json` has a new field:

```json
{ "package": "com.example.notes", "target": "desktop",
  "desktop": { "width": 960, "height": 640, "minWidth": 480, "minHeight": 320 } }
```

| `target` | Runs on | Window |
|---|---|---|
| `"mobile"` (the default: every app so far, no change to their packages) | the phone, and the desktop | on the desktop, a window with a phone's aspect ratio (393 × 852, scaled down on a small screen) that does **not** resize, with the phone's status bar drawn over its top, so the app lays itself out as on the phone |
| `"desktop"` | astraOS Desktop only | a window the user moves and resizes (`desktop` gives the first size and the minimum) |

* `tools/apkgtool` validates `target` and `desktop`; a package without them is byte for byte what it was.
* `astra check` (`sdk/astra_sdk/lint.py`): `E102` for a bad `target`; `E013`: `import Astra.Desktop` (the desktop controls)
  is for desktop apps only, a mobile app also runs on the phone.
* `astrad` (`packagemanager.cpp`): a desktop app is refused on a phone (install and scan); `info` carries
  `target` and `desktop`.
* **One app, two builds.** A desktop build has the same `package` as the mobile app it replaces on the desktop:
  `apps/<name>/` is the mobile one, `apps-desktop/<name>/` the desktop one (CMake: `astra_add_desktop_app`).
  Rewritten apps (a Files with a sidebar and columns) are desktop builds of the same package. Apps that make
  sense as they are stay mobile builds, in their phone window.
* **Market** (`astra-cloud`): one page and one catalog entry per package. Each version has up to two builds
  (`versions.target`; the same `versionCode` may exist once per target). The catalog is the asking device's:
  `GET /api/store/index.json?target=desktop|mobile`, or the User-Agent the runtime sends
  (`astraOS/<version> (<package>; desktop; ...)`), else a phone. A desktop gets the desktop build, or the mobile one
  when there is none; a phone gets the mobile build, and an app with a desktop build only is not offered to it
  (the page says it is for the desktop). Nothing is duplicated on the server.

## SysBoard on the desktop

`DesktopShell.qml` and its parts:

| File | What |
|---|---|
| `DesktopMenuBar.qml` | Activities, the app in front, the clock (opens the Notification Center), status, record pill (opens the Control Center) |
| `DesktopDock.qml` | pinned apps (`desktop.dock`), running apps, the bar under a running one, magnification, name, context menu (open / keep in Dock / quit), the Activities tile |
| `DesktopWindowLayer.qml`, `DesktopWindow.qml` | windows: stacking, move, resize on every edge, maximise, minimise into the Dock, close, the grip (a pill, buttons on hover), shadows, rounded corners, phone windows |
| `DesktopActivities.qml` | the open windows (live) and all the apps, with search, over a blur |
| `DesktopWidgets.qml` | the apps' home widgets on the desktop (`desktop.widgets`; Weather and Calendar by default) |
| `DesktopLock.qml` | the lock screen: the same lock screens as the phone (`LockSlots`: wallpaper, clock font, weight, height, widgets; hold three seconds to choose and edit), the user, a password field; the music pill |
| `DesktopSetup.qml` | the first start, full screen: language, Wi-Fi, the user, AstraID, appearance, phone |

Shortcuts (they work while an app has the focus): `Ctrl+Space` / `Meta+Space` Activities, `Ctrl+Alt+L` /
`Meta+L` lock, `Alt+Tab` the last window, `Ctrl+Q` close the window in front.

The animation engine is the phone's, unchanged: windows open and close on `Spring`s, the Dock's icons grow on
`Spring`s, panels drop in staggered. The secret that unlocks is the same `Lock` service as the phone's: a PIN of
4–8 digits there, a password of 4–128 characters on the desktop.

Launch: `scripts/dev-desktop.sh` (a window; `ASTRA_HEADLESS=1` on a virtual display, own build tree `build/desktop` and
root `out/desktop`), driven with `ASTRA_ROOT=out/desktop scripts/dev-ctl.sh`.

## Settings

Every setting of the phone exists on the desktop (the same `Settings` app, in its phone window, until its
desktop build lands), plus: Desktop (Dock, widgets, lock timeout, window), Phone Linker, PetalDrop. They are
`Settings` keys: `desktop.*`, `phonelinker.*`, `petaldrop.receive`.

## AstraID: phones and desktops

`astra-cloud`: a device has a `kind` (`phone` | `desktop`), sent by the device at sign-in
(`device.kind`; `AccountService` sends the one of `astra::Form`). `GET /api/id/devices` returns it; the
web page lists both. `account.state` carries `kind` and `deviceId`. `AccountService::request()` is how the
system services (Phone Linker, PetalDrop) talk to the server with the device's token, which apps never see.

## Phone Linker

One phone with one desktop and the other way round (`device_links`: both columns `UNIQUE`; 409 otherwise).

| Server (`lib/link.js`) | |
|---|---|
| `GET /api/device/link` | this device's link, and the free devices of the other kind it could link with |
| `POST /api/device/link {peer}` / `DELETE` | link / unlink |
| `POST /api/link/send {kind, payload}` | `notification`, `contacts`, `photo`, `dismiss`: kept for the other device, encrypted with the user's data key, until it fetches them (or 24 h) |
| `GET /api/link/events?after=&wait=55` | a long poll (the same as Find My Device's), `after` acknowledges |

`astrad` (`phonelinkservice.cpp`, service `phonelink`): the phone sends its notifications (not ongoing ones, not
the system's) as they are posted, and new photos (DCIM/Camera, Pictures; 12 MB at most each; only from the moment
the link was made); both sides send their contacts when they change and add what they lack. The desktop shows
the phone's notifications in its Notification Center and puts the photos in `Pictures/Phone`. Settings >
Phone Linker holds the switches (`phonelinker.enabled`, `.notifications`, `.contacts`, `.photos`).
What passes through the server is encrypted at rest, but **it does pass through it in clear to the server
process**: it is not end to end encrypted.

## PetalDrop

An AirDrop alternative that is not an app: there is no icon, the share sheet (`ShareSheet`, in Gallery, Files...)
lists the devices nearby and the system sends. `astrad`: `petaldropservice.cpp`, service `petaldrop`
(`peers`, `send`, `cancel`, `state`; the permission is `NEARBY_DEVICES`, a runtime one: the first share asks).

* Discovery: a UDP broadcast (port 47742) every 4 s from each device that may receive, plus the devices of the
  AstraID that the server lists with the addresses they reported (`POST /api/device/lan`).
* Trust: the devices of one AstraID share a secret from the server (`GET /api/device/petal`). Beacons carry an
  HMAC of the device id and time with it, and an offer is signed (HMAC-SHA256 over its file list): a device of
  your own is "mine" and is accepted without a question, any other is accepted or refused by the user.
* `petaldrop.receive`: `off`, `mydevices` (the default; only your own devices), `everyone` (a prompt each time).
* Transfer: TCP on port 47743: the offer (names, sizes), the answer, then each file followed by its SHA-256, which
  the receiver checks. Received files go to `Download/PetalDrop` and a notification opens them.
* **Not done**: the transfer is not encrypted on the wire (integrity yes, secrecy no); Bluetooth/AWDL-style discovery
  when there is no common network; sending through the server to a device far away.

## The ISO, the installer and recovery

`distro/build.sh iso` makes `astraOS-<version>-desktop.iso`: a live Debian (live-boot, squashfs, GRUB for BIOS and UEFI) that
starts with `astra.live=1` on the kernel command line. `astra-live.service` then marks the system as live (`/run/astra/live`),
creates the `astra-live` user and settings that skip the setup and the lock, and SysBoard starts in **recovery mode**
(`Host.installer`): no widgets, no lock, a Dock with the Installer, Disk Utility, Browser and Terminal, and a Utilities card in
the middle (Install astraOS, Disk Utility, Browser, Terminal, Restart, Shut Down), as the macOS recovery does.

* **Install astraOS** (`apps-desktop/installer`): Welcome, the disk, the question ("Erase and install?", with what is lost), the
  progress, Restart. The work is `astrad`'s `installer` service (`installerservice.cpp`, permission `MANAGE_DISKS`, only in the live
  system, never on the disk the system runs from, only on devices lsblk lists) and `distro/overlay/usr/lib/astra/installer/install.sh`:
  GPT with a BIOS boot partition, an EFI partition and the system (ext4), `rsync` of the live file system, `fstab` by UUID, the host
  name, the Linux user that owns the home directory, GRUB for UEFI (and the removable path) and BIOS. The installed system starts
  with the usual setup wizard (a new `/data`, no `first-boot-done`).
* **Disk Utility** (`apps-desktop/diskutil`): disks and volumes, erase (ext4, FAT32, exFAT, NTFS, swap), add and delete partitions,
  mount and unmount. Each change asks first.
* **Browser, Terminal**: Linux programs listed as apps. `/Applications/<Name>.legacy.json` gives the package, name, icon and
  `legacy: {exec, args, appId, user}`; the package manager lists it, astrad starts it as that user on SysBoard's Wayland
  socket, and the window is matched to the package by `app_id`. Any other Wayland program draws a plain resizable window.
  The recovery browser is Firefox ESR: **Planet** needs Qt WebEngine, which the Qt astra is built with here does not have.

## Updates (OTA)

Like the phone: GitHub releases of this repository's releases (`OTA_REPOSITORY`, `ro.astra.ota.repo`, default `tsryzenstech/astra`; the workflow is
`.github/workflows/desktop-iso.yml`, **not committed until the desktop is finished**), pre-releases `<version>-rev<N>` and releases
`<version>`, the channel is the build's. Each release carries the ISO, `astraOS-<tag>-desktop-system.tar.gz` (`/system` and
`/Applications`) and `ota.json` (`distro/build.sh ota`). The update service downloads and checks it, "Install and restart" runs
`systemctl reboot`, and `astra-ota-apply.service` swaps the trees with renames at the next start (the old ones stay as `*.old`).
The kernel, firmware and drivers are Debian's and update with `apt`.

## Input

Qt's eglfs input in astra's Qt build is evdev only: a keyboard and a plain mouse work, a **touchpad does not**. On the desktop SysBoard
turns Qt's eglfs input off (`QT_QPA_EGLFS_DISABLE_INPUT`) and starts its own: **libinput** for pointers, touchpads and touch screens
(`sysboard/inputbridge.cpp`: tap to click, two-finger scroll and click, natural scrolling, palm and typing rejection, acceleration, touch
points) and Qt's evdev keyboard plugin. The pointer is an arrow drawn by the shell (`Main.qml`, `Host.pointerPosition`): Qt's own eglfs
cursor did not show. If libinput cannot start, Qt's evdev mouse and touch plugins take over (no touchpad). The recovery card works with Up,
Down and Return as well. `astra.debug` on the kernel command line logs what the devices deliver. Verified in QEMU (USB keyboard and
mouse: keys, moves, clicks, typing in the Terminal); **not on a real touchpad**.

## Desktop details

* The widgets on the left of the desktop: at most **two**, or one **giant folder** (a tall tile with apps); drag to reorder, right
  click for Remove / Move / Add Widget / Add Giant Folder (`desktop.widgets`). The lock screen has no widgets.
* The menu bar always has Bluetooth, Wi-Fi and a battery glyph (dimmed when there is nothing to report) and opens the Control Center.
* Notification banners are cards at the top right; dialogs (permissions, confirmations) are small cards in the middle.
* The boot animation is the phone's, smaller (`logo_width_percent`, `logo_height_percent` in the desktop's `desc.txt`).
* Runtime permissions of the system's own apps are granted from the start (Files has its files at once).
* Wi-Fi: NetworkManager (`network/nm.cpp`); Bluetooth: BlueZ; power: `systemctl`; NVIDIA: `first-boot.sh` installs Debian's driver.

## Milestones

| | | Status |
|---|---|---|
| M1 | `target` in `app.json`, `apkgtool`, `astra check`, `packagemanager`, `/Applications`, `astra::Form` | done; `tests/test_apkgtool.py` |
| M2 | Market: one page, two builds; AstraID device kinds and links (server) | done; `astra-cloud/scripts/smoke-desktop.mjs` |
| M3 | DesktopShell: bar, Dock, windows, Activities, lock screen, setup | done and rendered (below); the feel (animations, pointer) needs a real screen |
| M4 | PetalDrop and Phone Linker in astrad; ShareSheet; Settings pages | done, tested against astrad (below); the phone side of Phone Linker and signed PetalDrop transfers are not |
| M5 | Desktop apps, `Astra.Desktop` controls | Files done; the other apps run as mobile builds in phone windows; no Market client for the desktop yet |
| M6 | The Debian image, systemd units, drivers, OTA | the ISO builds and boots in QEMU (recovery, Terminal, install); real hardware: tested by the user, input and drivers still being fixed |

## Verified, and not

Run on this machine (WSL2, Qt 6.8.3, a virtual X display, software rendering), headless:

* `tests/test_apkgtool.py` (12 tests, the target field and the lint rules) pass.
* `astra-cloud/scripts/smoke-desktop.mjs`: one app with a mobile and a desktop build is one catalog entry and one page,
  each device gets its own build, a desktop-only app is not offered to a phone, phone and desktop link (one with one),
  events cross the long poll, PetalDrop's key and addresses. All pass.
* DesktopShell rendered at 1280 × 720 (`scripts/dev-desktop.sh`, screenshots): the setup (full screen), the lock screen (with
  its widgets, the user, the password field), the desktop (menu bar, widgets, Dock), Activities with live window
  thumbnails, a desktop app (Files) in a resizable window, and a mobile app (Settings) in a phone window, scaled to
  fit the screen.
* `tests/manual/petaldrop-receive.py` and `petaldrop-send.py` against a running astrad: offers, the user's answer through the
  system dialog, files whole with their SHA-256, a corrupted file refused, `mydevices` refusing a stranger, sending to a
  device announcing itself. All pass.
* `tests/manual/phonelink-desktop.py` against astrad and a real astra-cloud server: the desktop signs in as a desktop, links
  with a phone played over HTTP, and a notification, contacts and a photo from it arrive. All pass.

* The ISO in QEMU (KVM, BIOS, std VGA, USB keyboard and mouse): it boots to the recovery (Install astraOS, Disk Utility, Browser, Terminal);
  the Terminal opens and runs commands; keys, pointer moves and clicks reach the shell; **an unattended install** (`astra.autoinstall=/dev/vda`,
  `scripts/dev-qemu.sh`) copies the system, installs GRUB and the installed disk boots silently into the boot animation and the setup wizard
  (full screen "Welcome to astraOS"); **a dual boot install** (`--root /dev/vda4 --esp /dev/vda2 --bootdisk /dev/vda --dual`, next to a
  system already on the disk) leaves the other system alone, finds it with os-prober and shows GRUB's menu at every start. Running these
  found and fixed: `sfdisk` missing from the image, rsync's exit status killing the installer silently, `grub-install` failing on a BIOS
  start because of the EFI variables, the Japanese "hello" of the setup drawn as boxes (no CJK font), a disk check line on the screen at boot.

**Not verified** (be careful with anything below this line):

* The install from the **Install astraOS app** (the click path: disk list, erase/dual choice, the partition size slider); the tests above ran
  the same `install.sh` through the unattended hook. UEFI boot of an installed system (QEMU ran BIOS), Secure Boot.
* BIOS boot still prints "GRUB loading." and "Welcome to GRUB!" for a moment (GRUB's own first stage; UEFI GRUB prints nothing when hidden).

* Moving, resizing, maximising and minimising windows with a pointer, the Dock's magnification, the Alt+Tab and the keyboard
  shortcuts, the context menus, typing in the lock screen and in Files (the dev automation has taps and swipes only).
* Any real GPU, a real display, HiDPI, multiple displays, the NVIDIA driver; "smooth from the first frame" is a claim for the
  design (the same engine as the phone), not a measurement.
* The phone's side of Phone Linker (sending notifications, photos and contacts) and PetalDrop's account signed transfers ("my
  devices"), which need two devices; the PetalDrop transfer is not encrypted on the wire.
* The ISO on **real hardware**: it boots there, but the first real-hardware tests found no mouse, keyboard or touchpad in the recovery (fixed
  since, see Input, and verified only in QEMU) and missing drivers are suspected (firmware and microcode packages were added, GPU paths
  other than the virtual one are not tested). NetworkManager on a real Debian, the OTA apply on a real disk, the setup on a real first boot.
* The Market client (`apps/market`) on the desktop (it runs in a phone window; its requests carry the runtime's User-Agent, which says "desktop" there, so the
  server gives it the desktop builds: that path is tested on the server only, not through the app), and the web page of the cloud.
* The other mobile apps in phone windows beyond Settings; their desktop builds (only Files was rewritten).
