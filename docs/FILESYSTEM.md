# Filesystem layout

astraOS uses Android's partitioning and directory conventions on top of a
regular Linux userland.

## Partitions

| Partition | Contents | Mounted at | Mode |
|---|---|---|---|
| `boot` | kernel, DTB, ramdisk (first stage init) | – | – |
| `super` → `system` | root filesystem (system-as-root) | `/` | read-only |
| `super` → `vendor` | device specific files | `/vendor` | read-only |
| `super` → `product` | product customisation | `/product` | read-only |
| `userdata` | user data | `/data` | read-write, ext4 |

`system`, `vendor` and `product` are logical partitions inside `super`
(dynamic partitions), created with `lpmake` and mapped at boot by init.

## Root

```
/
├── system/
│   ├── bin/            init, astrad, sysboard, astra-app, bootanim, busybox...
│   ├── lib/            libraries, Qt plugins, kernel modules, firmware
│   ├── etc/            init/*.rc, settings/defaults.json, passwd, group, fonts/
│   ├── framework/qml/  Astra.Core, Astra.Controls, Astra.Animation
│   ├── app/<Name>/<package>.apkg        system apps
│   ├── priv-app/<Name>/<package>.apkg   privileged system apps (Settings)
│   ├── fonts/          Poppins
│   ├── media/          bootanimation/, wallpapers/, brand/
│   └── build.prop      system properties
├── vendor/             build.prop, etc/fstab, etc/init/*.rc, firmware/
├── product/            build.prop, app/
├── data/
├── sdcard -> data/media/0
├── bin -> system/bin   sbin -> system/bin   lib -> system/lib
├── etc -> system/etc   usr -> system        var -> data/var
└── dev proc sys run tmp mnt metadata odm    (mount points)
```

## /data

```
/data
├── app/<package>/            installed packages
│   ├── base.apkg             (user installed apps only)
│   └── code/                 extracted package contents
├── data/<package>/           private app data (owned by the app uid, 0700)
├── user/0 -> /data/data
├── system/                   astrad state: packages.json, settings.json,
│                             notifications.json, locksettings.json, weather.json
├── media/0/                  shared storage (/sdcard): Music, Pictures...
├── misc/  local/  var/
```

## Properties

Build properties are read from `/system/build.prop`, then
`/vendor/build.prop`, then `/product/build.prop` (later files win).

| Property | Meaning |
|---|---|
| `ro.astra.version`, `ro.astra.release`, `ro.astra.api_level` | OS version |
| `ro.product.device`, `ro.product.model`, `ro.product.manufacturer` | device |
| `ro.astra.ui.scale` | UI scale factor (logical → physical pixels) |
| `ro.system.wallpaper` | default wallpaper |
| `ro.vendor.backlight`, `ro.vendor.torch` | sysfs overrides for brightness/torch |

## Development trees

Every component resolves paths through `astra::Paths`. Setting
`ASTRA_ROOT=<dir>` relocates the whole tree (e.g. `out/root/system`,
`out/root/data`, `out/root/dev/socket/astrad`), which is how astraOS runs on
a desktop.
