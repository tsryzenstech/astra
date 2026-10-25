# The .apkg package format

astraOS apps are distributed as `.apkg` files: a single binary container
with the app manifest, a file index and the (zlib compressed) files, closed
by a SHA-256 checksum. Packages are reproducible: building the same sources
twice gives identical bytes.

Tools: `tools/apkgtool/apkgtool.py` (pack, info, list, verify, unpack).
Device side reader: `astra::Apkg` in `frameworks/libastra`.

## Layout

All integers are little endian.

```
offset  size  field
------  ----  -------------------------------------------------------
Header (64 bytes)
0       8     magic "ASTRAPKG"
8       2     format version (1)
10      2     flags (0; bit 0 reserved for signed packages)
12      4     header size (64)
16      4     manifest offset
20      4     manifest size
24      4     index offset
28      4     index size
32      4     entry count
36      4     reserved
40      8     data offset
48      8     data size
56      8     reserved

Manifest   UTF-8 JSON (app.json, keys sorted, no whitespace)

Index      entry count × entry:
  0     2     path length (bytes)
  2     1     compression (0 = stored, 1 = zlib)
  3     1     type (0 = regular file)
  4     4     unix mode
  8     8     offset of the stored data, relative to the data section
  16    8     stored size
  24    8     uncompressed size
  32    32    SHA-256 of the uncompressed contents
  64    n     path (UTF-8, '/' separated, relative, no "..")

Data       stored file contents

Trailer (40 bytes)
0       32    SHA-256 of every byte before the trailer
32      8     "APKGEND\0"
```

## Manifest (app.json)

```json
{
    "package": "com.example.hello",
    "name": "Hello",
    "version": "1.0.0",
    "versionCode": 1,
    "description": "Says hello.",
    "main": "qml/Main.qml",
    "icon": "icon.svg",
    "background": "#000000",
    "launcher": { "visible": true },
    "permissions": ["astra.permission.INTERNET"],
    "widgets": [
        { "id": "greeting", "name": "Greeting", "qml": "widgets/Greeting.qml", "size": "small" }
    ]
}
```

| Key | Required | Notes |
|---|---|---|
| `package` | yes | reverse domain name, lowercase |
| `name`, `version` | yes | shown to users |
| `versionCode` | yes | integer ≥ 1, increases with every release |
| `main` | yes | root QML component of the app |
| `icon` | yes | square artwork, shaped by the system |
| `background` | no | splash colour while the app starts |
| `permissions` | no | see [IPC.md](IPC.md#permissions) |
| `widgets` | no | lock screen widgets, see [APPS.md](APPS.md#lock-screen-widgets) |

## Installation

astrad's package manager verifies the checksums, extracts the package to
`/data/app/<package>/code`, assigns a uid and creates
`/data/data/<package>`. System apps found in `/system/app`,
`/system/priv-app` and `/product/app` are (re)installed at boot when their
checksum changes; they are owned by root and cannot be uninstalled.
