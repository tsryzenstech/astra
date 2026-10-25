# Writing apps

An astraOS app is a directory with an `app.json` manifest, an icon and QML
files, packed into an [.apkg](APKG.md). Apps run in their own process
(`astra-app`), with their own uid and private data directory, as Wayland
clients of SysBoard.

```
hello/
├── app.json
├── icon.svg
├── qml/Main.qml
└── widgets/Greeting.qml
```

```qml
// qml/Main.qml
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    title: "Hello"

    ListGroup {
        title: "Example"
        ListItem {
            text: "Post a notification"
            chevron: true
            onClicked: Notifications.post("Hello", "Sent from my first astraOS app")
        }
    }
}
```

```bash
python3 tools/apkgtool/apkgtool.py pack hello -o hello.apkg
```

System apps are packed by CMake (`astra_add_app()` in `apps/CMakeLists.txt`).

## APIs

`import Astra.Core`

| Singleton / type | Purpose |
|---|---|
| `Application` | `packageName`, launch `args`, `intent(args)` signal for deep links while running, `dataDir`, `mediaDir` |
| `Notifications` | model of the app's notifications, `post(title, body)`, `dismiss(id)` |
| `MediaSession` | publish what the app plays (title, artist, artwork, position, playing); receive `command(action, position)` |
| `Settings` | read system settings (`Settings.values["key"]`) |
| `System` | battery, radios, brightness, build properties (`System.property(key)`) |
| `Weather` | current conditions |
| `Packages` | installed packages, `launch(package, args)` |

`import Astra.Controls` – design system: `Page`, `PageStack`, `ListGroup`,
`ListItem`, `Switch`, `Button`, `TextField`, `Slider`, `AppIcon`, `Icon`
(system icon set), `BatteryGlyph`, `WeatherGlyph`, `Theme` (colours, type
scale, metrics), `PlaceholderApp`.

`import Astra.Animation` – see [ANIMATION.md](ANIMATION.md).

The status bar is drawn by SysBoard over every app: keep the top
`Theme.statusBarHeight` pixels free of controls (`Page` already does).

## Launch arguments and deep links

Apps receive JSON arguments from whoever launched them (`Application.args`).
If the app is already running, the new arguments arrive through
`Application.onIntent`. Settings uses this for `{ page: "lockscreen" }` and
`{ page: "appinfo", package: "..." }`.

## Lock screen widgets

Declare widgets in `app.json`:

```json
"widgets": [
    { "id": "greeting", "name": "Greeting", "qml": "widgets/Greeting.qml", "size": "small" }
]
```

| Size | Slot (logical px) | Lock screen units |
|---|---|---|
| `small` | 41 × 41 content area | 1 |
| `wide` | 103 × 41 content area | 2 |

The lock screen has 4 units. Users pick and order widgets in
Settings › Lock Screen; the selection is stored in the `lockscreen.widgets`
setting as `"<package>/<id>"` keys. Widget QML is rendered by SysBoard on a
dark glass tile: the root item fills the content area and may use
`Astra.Core` (e.g. `Weather`, `System`, `MediaController`) and
`Astra.Controls`. Keep widgets light: they are created whenever the lock
screen shows.

## Permissions

See [IPC.md](IPC.md#permissions).
