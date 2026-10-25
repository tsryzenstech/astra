# Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Apps (.apkg)            Settings · Tune · Weather · ... (astra-app)  │
│   QML + Astra.Controls / Astra.Core / Astra.Animation                │
├────────────────────────────── Wayland ───────────────────────────────┤
│ SysBoard   compositor + shell: status bar, lock screen, home screen, │
│            Control/Notification Center, app transitions              │
├────────────────────────── /dev/socket/astrad ────────────────────────┤
│ astrad     packages · activities · notifications · settings · lock   │
│            media sessions · hardware · weather · system/power        │
├──────────────────────────────────────────────────────────────────────┤
│ init (PID 1) · bootanim · udevd             Qt 6 · Mesa · musl       │
├──────────────────────────────────────────────────────────────────────┤
│ Linux kernel (mainline)                     DRM/KMS · evdev · rfkill │
└──────────────────────────────────────────────────────────────────────┘
```

## Boot

1. The bootloader loads `boot.img`: kernel, device tree and a tiny ramdisk
   containing only `/init` (a static build of astra init) and
   `/first_stage.fstab`.
2. **First stage init** finds the `super` partition, parses its logical
   partition metadata (the format written by `lpmake`) and creates a
   device-mapper target for each logical partition
   (`/dev/block/mapper/<name>`). It mounts `system` as the new root plus
   `vendor` and `product`, deletes the ramdisk and switches root.
3. **Second stage init** (`/system/bin/init second_stage`) mounts the
   pseudo filesystems, runs the `.rc` files from `/system/etc/init`,
   `/vendor/etc/init` and `/product/etc/init` through the triggers
   `early-init → init → fs → post-fs-data → boot` and supervises services
   (restart with back-off, critical services, control socket
   `/dev/socket/init` for `start/stop/restart <svc>`, `reboot`, `poweroff`).
4. `udevd` populates `/dev`, then the **boot animation** shows the logo.
5. `fs` mounts `/data` (formatted on first boot when blank) and
   `post-fs-data` creates the `/data` layout.
6. `boot` starts `astrad` (class `core`) and `SysBoard` (class `main`).
   SysBoard asks the boot animation to fade out, takes the display through
   KMS and reports "boot completed" to astrad.

## Processes and identities

| Process | User | Notes |
|---|---|---|
| init | root | PID 1 |
| udevd | root | device nodes, firmware, module autoloading |
| bootanim | graphics | exits when SysBoard starts |
| astrad | root | owns `/data/system`, launches apps |
| sysboard | system | groups graphics, input, video, audio |
| apps | 10000+ | one uid per package, private `/data/data/<package>` |

User ids follow Android numbering (`system` = 1000, apps from 10000).
The caller of every IPC request is identified by the kernel (`SO_PEERCRED`)
and mapped to a package by astrad; permissions are declared in `app.json`
and granted at install time (privileged apps in `/system/priv-app` get all
the permissions they request, other apps only the normal ones).

## Display

SysBoard is a Qt Quick Wayland compositor running on `eglfs` (KMS). Apps are
Qt Quick Wayland clients started by astrad. Each app window is an
`xdg_toplevel` whose `app_id` is the package name: that is how SysBoard
matches windows with launcher icons and animates them. The on-screen
keyboard (Qt Virtual Keyboard) lives in SysBoard and serves apps through the
Wayland text-input protocols.

## Motion

Everything that moves goes through the AnimationEngine (`Astra.Animation`),
see [ANIMATION.md](ANIMATION.md).
