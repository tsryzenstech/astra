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

## Updates (OTA)

Phones update from the GitHub releases of their device repository (`docs/VERSIONING.md`). A desktop does the same
from the release of the desktop image repository (`OTA_REPOSITORY` of the image, `ro.astra.ota.repo`; the
channel is the build's, Delta for pre-releases and Stable for releases, as on the phone). A release carries
`ota.json` and `astraOS-<tag>-desktop-system.tar.zst`: `/system` and `/Applications`. The update service
downloads and verifies it, and a unit at the next boot swaps the trees (`/system.new` → `/system`, atomically, the old
one kept as `/system.old` for a rollback). The kernel, firmware and drivers come from Debian through `apt` (the
distribution's own updates), not from astraOS's OTA.

## Image

`distro/` (see its README): `build.sh` builds the Debian root file system with `mmdebstrap`, installs the
astra tree (`cmake --install` with `-DASTRA_FORM=desktop`), the systemd units, the package list (kernel,
firmware, Mesa, PipeWire, NetworkManager, the NVIDIA/AMD/Intel drivers), and writes a UEFI-bootable image (`.img`)
for a USB stick. The boot animation is the phone's (`core/bootanimation`, shown by a systemd unit before
SysBoard, and handed over as on the phone).

## Milestones

| | | Status |
|---|---|---|
| M1 | `target` in `app.json`, `apkgtool`, `astra check`, `packagemanager`, `/Applications`, `astra::Form` | done, tests (`tests/test_apkgtool.py`) |
| M2 | Market: one page, two builds; AstraID device kinds, links | done on the server, `astra-cloud/scripts/smoke-desktop.mjs` |
| M3 | DesktopShell: bar, Dock, windows, Activities, lock screen, setup | built and rendered headless (screenshots, see below); animations and pointer behaviour need a real screen |
| M4 | PetalDrop and Phone Linker in astrad; ShareSheet; Settings pages | written; see "Verified" |
| M5 | Desktop apps (Files first), `Astra.Desktop` controls, Market client for the desktop | Files: see "Verified" |
| M6 | The Debian image, systemd units, drivers, OTA | scaffold in `distro/`; **not built or booted** |

## Verified, and not

(Kept up to date with the work; see the commit messages.)
