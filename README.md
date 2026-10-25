<p align="center">
  <img src="prebuilt/media/bootanimation/logo.png" alt="astra" width="280">
</p>

# astraOS

astraOS is a mobile operating system built on the **Linux kernel**. It is
**not based on Android**: there is no ART, no Bionic and no Android framework.
It does keep the parts of Android that make phones easy to build and flash
(dynamic partitions in `super`, `boot.img`, `vendor.img`, an Android-like
filesystem layout), so it installs with `fastboot` like any custom ROM.

This repository holds the system code. Device builds live in their own
repositories; the first supported device is the Redmi Note 10 Pro
(`sweet`): [astra_device_xiaomi_sweet](../astra_device_xiaomi_sweet).

> Status: **Developer Preview 1**. The system UI, services and app platform
> run end to end on a desktop Linux machine (see [Development](#development)).
> Device bring-up on sweet is the next milestone.

## What is in the box

| Component | Path | What it does |
|---|---|---|
| **init** | `core/init` | PID 1. First stage (ramdisk) maps the logical partitions inside `super` with device-mapper and switches root; second stage runs Android-style `.rc` scripts and supervises services. |
| **Boot animation** | `core/bootanimation` | The astra logo, centered on black, drawn with KMS dumb buffers until SysBoard takes over. |
| **astrad** | `services/astrad` | The system server: package manager, activity manager (one uid per app), notifications, settings, lock screen PIN, media sessions, hardware, weather, power. |
| **SysBoard** | `sysboard` | The Wayland compositor and system shell: status bar, lock screen, home screen (launcher, not replaceable), Control Center, Notification Center and app transitions. |
| **AnimationEngine** | `frameworks/animation` | The motion system (`Astra.Animation`): analytic, interruptible springs, gesture velocity tracking, spring easing curves and system-wide motion tokens. |
| **libastra** | `frameworks/libastra` | Shared C++ library: IPC client, `.apkg` reader, build properties, filesystem paths. |
| **Astra.Core / Astra.Controls** | `frameworks/qml` | QML APIs for apps and the shell (system services, design system components, icon set). |
| **App runtime** | `frameworks/runtime` | `astra-app`, the process every app runs in. |
| **Apps** | `apps/` | Settings (with developer testing tools), Tune (music player) and placeholders for Weather, Clock, Themes, Market, MeetUp, Gallery, Phone, Messages, Planet, Camera and Tips. |
| **apkgtool** | `tools/apkgtool` | Builds and inspects `.apkg` app packages. |

### System UI highlights

- **Lock screen** with a customizable clock font and widgets (any app can
  provide widgets), torch/camera shortcuts that grow while held, a music
  player that appears only while something plays and expands into a full
  player, and an iOS-style PIN pad. Long press opens Settings › Lock Screen
  after the PIN.
- **Home screen** with the weather greeting, Cosmo/Planet search, pages and
  a dock. Long press an icon to bring it forward over a blurred screen with
  *App Info / Edit Home Screen / Uninstall* (system apps, installed by root,
  cannot be uninstalled); drag icons to rearrange them, the others make room.
- **App launch**: the icon itself grows into the app with a spring; swipe
  up from the bottom edge to send it back into its icon.
- **Notification Center** (pull down on the left) and **Control Center**
  (pull down on the right): the screen blurs in place and each component
  drops in with a bouncy, staggered spring. Swipe sideways between them; past
  the edges they stretch and snap back like a magnet.
- **Status bar** owned by SysBoard, fixed on every screen.

## Filesystem layout

```
/                      system.img (read-only, system-as-root)
├── system/            bin, lib, etc, framework/qml, app, priv-app, fonts, media
├── vendor/            vendor.img: device props, fstab, init scripts, firmware
├── product/           product.img: product customisations
├── data/              userdata: app/, data/<package>, system/, media/0
├── sdcard -> data/media/0
└── bin, lib, etc, usr -> system/...
```

Details: [docs/FILESYSTEM.md](docs/FILESYSTEM.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Filesystem layout](docs/FILESYSTEM.md)
- [The .apkg package format](docs/APKG.md)
- [Writing apps and lock screen widgets](docs/APPS.md)
- [IPC protocol and system services](docs/IPC.md)
- [AnimationEngine](docs/ANIMATION.md)
- [Development setup](docs/DEVELOPMENT.md)

## Development

Requirements: Linux (or WSL2), CMake ≥ 3.21, Ninja, a C/C++17 compiler,
Python 3, Qt ≥ 6.5 (Core, Gui, Network, Qml, Quick, QuickControls2,
WaylandCompositor, Svg, Multimedia), libdrm and libpng.

```bash
scripts/dev-run.sh
```

This builds everything, installs it into `out/root` and starts astrad and
SysBoard in a window. Apps launched from the home screen run as Wayland
clients of SysBoard, exactly as on a phone. `F12` is the power key.
`scripts/dev-ctl.sh` drives the UI from scripts (tap, swipe, screenshot).

Tests:

```bash
cmake -S . -B build -G Ninja && cmake --build build && ctest --test-dir build
```

## Roadmap

- Device bring-up on sweet (display, touch, GPU on the mainline kernel)
- Wi-Fi and Bluetooth managers behind the existing Settings toggles
- Real apps behind the placeholders, starting with Phone, Messages and Camera
- Package signing for `.apkg`
- Android compatibility layer

## License

astraOS is released under the [Apache License 2.0](LICENSE). The Poppins
typeface is licensed under the [SIL Open Font License](prebuilt/fonts/OFL.txt).
