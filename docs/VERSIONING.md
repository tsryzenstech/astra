# Versioning

`version.json` at the root of the repository is the single source of truth:

```json
{ "major": 27, "minor": 0, "channel": "stable", "codename": "Candyland", "api_level": 1 }
```

astraOS **26.0** is the first version after the development builds (0.1d).
astraOS **27.1 “Candyland”** is the current version.
A new version raises `minor` (26.0 → 26.1) or `major` (26.x → 27.0).

| Channel | Letter | Meaning |
|---|---|---|
| delta | d | developer previews (0.1d) |
| beta | b | feature complete, testing |
| stable | (none) | releases |

`cmake/AstraVersion.cmake` turns it into the build properties every component
reads (`ro.astra.version`, `ro.astra.channel`, `ro.astra.codename`,
`ro.astra.api_level`, `ro.astra.build.number`, `ro.astra.build.id`,
`ro.astra.build.date`, `ro.astra.build.commit`, `ro.astra.ota.url`).

* **Build number** – commits on the branch (`git rev-list --count HEAD`); it only
  grows, so it orders builds of the same channel.
* **Build ID** – `ASTRA.<version>.<yyyymmdd>.<build number>`, e.g. `ASTRA.27.0.20261107.3`.
* **Version suffix** – `-DASTRA_VERSION_SUFFIX=-rev3` adds to `ro.astra.version`
  (`26.0-rev3`): the device repositories pass it for pre-release builds.

## Device builds: releases and pre-releases

Each device repository (e.g. `astra_device_xiaomi_sweet`) publishes its builds
as GitHub releases:

| Build | Started by | Published as | Tag / version |
|---|---|---|---|
| **pre-release** ("delta" build) | a new astraOS version, a push to the device repository | GitHub pre-release | `<version>-rev<N>`: `26.0-rev1`, `26.0-rev2`… (N starts at 1 for each version) |
| **release** | a maintainer, by hand (Actions › build › Run workflow) | GitHub release (latest) | `<version>`: `26.0` (`26.0-rev<N>` once `26.0` exists) |

Changing the version in `version.json` on `main` starts a pre-release build of
every device: the `version` workflow sends the device repositories an
`astra-version` event (with the `DEVICE_DISPATCH_TOKEN` secret), and each device
also checks for a version without a build every few hours. The maintainer then
decides: run the device's workflow by hand for a release, or turn the
pre-release into a release on GitHub (Edit › uncheck "Set as a pre-release").

## OTA

Phones update from the GitHub releases of their device repository: the
repository is `OTA_REPOSITORY` in the device's `board.conf` (the build writes it
as `ro.astra.ota.repo`), so a fork that builds for a phone sets its own and its
phones update from its releases.

| Channel | Offers | Phones on it |
|---|---|---|
| **stable** | releases (manual builds) | those installed from a release, and anyone who picks it |
| **prerelease** | releases and pre-releases (the automatic "delta" builds) | those installed from a pre-release, and anyone who picks it |

The phone starts on its build's channel (`ro.astra.ota.channel`); Settings ›
Software Update changes it. Each device build publishes, next to its zip:

* `astraOS-<tag>-<device>-super.img.gz`, the new `super` partition (sparse),
* `astraOS-<tag>-<device>-esp.fat.gz`, the new EFI partition (kernel, ramdisk, device tree),
* `ota.json`, which describes them:

```json
{ "format": 1, "device": "sweet", "tag": "27.0-rev2", "version": "27.0-rev2",
  "codename": "Candyland", "channel": "prerelease", "time": 1762531200,
  "notes": ["What changed", "..."], "astra": "<commit>", "device_commit": "<commit>",
  "files": { "super": { "name": "…", "size": 0, "sha256": "…", "raw_size": 0, "raw_sha256": "…" },
             "esp": { "…": "…" } } }
```

A release is newer when its `time` is later than the phone's
(`ro.astra.ota.time`). The update service (astrad, `update.*`) looks a minute
after the start and twice a day, and notifies when one is available. It
downloads both files to `/data/ota`, checks them, unpacks them into
`/data/ota/apply` and checks them again; "Install and restart" restarts the
phone, and the first stage of init writes them before it mounts anything from
`super` (`core/init/ota.c`), then restarts into the new system. An interrupted
write starts again on the next start (three attempts).

`notes` is the list of commits of astra and of the device repository since the
previous build of the same channel (`scripts/release-notes.py` in the device
repository). The build keeps its own in `/vendor/etc/astra-release.json`: after
each new version the phone shows a notification that opens Tips on "What's new".
