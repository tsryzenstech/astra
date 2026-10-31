# Versioning

`version.json` at the root of the repository is the single source of truth:

```json
{ "major": 26, "minor": 0, "channel": "stable", "codename": "Blossom", "api_level": 1 }
```

astraOS **26.0** is the first version after the development builds (0.1d).
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
* **Build ID** – `ASTRA.<version>.<yyyymmdd>.<build number>`, e.g. `ASTRA.26.0.20261031.3`.
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

The update service (Settings › Software Update) reads
`<ro.astra.ota.url>/<device>/<channel>.json`:

```json
{ "version": "26.0", "codename": "Blossom", "build": 42,
  "url": "https://…/astraOS-26.0-sweet.zip", "sha256": "…", "size": 812345678,
  "notes": "What changed" }
```

A build is offered when its `build` is greater than the phone's
`ro.astra.build.number`. The package is downloaded to `/data/ota` and verified;
installing it needs the astraOS recovery (planned).
