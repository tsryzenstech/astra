# Versioning

`version.json` at the root of the repository is the single source of truth:

```json
{ "major": 0, "minor": 1, "channel": "delta", "codename": "Blossom", "api_level": 1 }
```

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
* **Build ID** – `ASTRA.<version>.<yyyymmdd>.<build number>`, e.g. `ASTRA.0.1d.20261029.3`.

## OTA

The update service (Settings › Software Update) reads
`<ro.astra.ota.url>/<device>/<channel>.json`:

```json
{ "version": "0.1d", "codename": "Blossom", "build": 42,
  "url": "https://…/astraOS-sweet-0.1d-42.zip", "sha256": "…", "size": 812345678,
  "notes": "What changed" }
```

A build is offered when its `build` is greater than the phone's
`ro.astra.build.number`. The package is downloaded to `/data/ota` and verified;
installing it needs the astraOS recovery (planned).
