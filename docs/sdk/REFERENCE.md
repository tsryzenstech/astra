# astraOS SDK reference

Generated from the sources by `sdk/tools/gen_reference.py`: do not edit by hand.

```qml
import QtQuick
import Astra.Core       // the system: settings, apps, files, notifications...
import Astra.Controls   // the UI: every app is built from these
```

## Astra.Controls

### AppIcon

Square app artwork clipped to the astraOS icon shape.

| Property | Type | Default | |
|---|---|---|---|
| `source` | url | |  |
| `size` | real | `60` |  |
| `round` | bool | `false` | circular badge (notifications) |
| `radius` | real (read-only) | |  |

### Button

Pill shaped button.

| Property | Type | Default | |
|---|---|---|---|
| `text` | string | |  |
| `iconName` | string | |  |
| `primary` | bool | `true` |  |
| `destructive` | bool | `false` |  |
| `enabled` | bool | `true` |  |

Signals: `clicked()`

### Card

Rounded surface for free-form content. With `accented` it uses the accent gradient (the playful, vivid surfaces of the design language).

| Property | Type | Default | |
|---|---|---|---|
| `content` | alias | `inner.data` |  |
| `padding` | real | `18` |  |
| `accented` | bool | `false` |  |
| `pressable` | bool | `false` |  |

Signals: `clicked()`

### EmptyState

Centered icon, title and message for empty lists.

| Property | Type | Default | |
|---|---|---|---|
| `iconName` | string | `"info"` |  |
| `title` | string | |  |
| `message` | string | |  |

### Icon

A symbolic icon from the system icon set, optionally tinted. Icon { name: "settings"; size: 24; color: "black" }

| Property | Type | Default | |
|---|---|---|---|
| `name` | string | |  |
| `size` | real | `24` |  |
| `color` | color | `"white"` |  |
| `tinted` | bool (read-only) | |  |

### IconButton

Round button holding a symbolic icon.

| Property | Type | Default | |
|---|---|---|---|
| `iconName` | string | |  |
| `size` | real | `44` |  |
| `color` | color | `Theme.surfaceRaised` |  |
| `iconColor` | color | |  |
| `enabled` | bool | `true` |  |

Signals: `clicked()`, `pressAndHold()`

### ListGroup

Rounded card that stacks ListItems with hairline separators.

| Property | Type | Default | |
|---|---|---|---|
| `content` | alias | `column.data` |  |
| `title` | string | | optional section label shown above the card |
| `footer` | string | | optional explanation shown below the card |

### ListItem

A row inside a ListGroup: label, optional subtitle/value, and an accessory (chevron, switch or nothing). Child items are placed with the trailing accessories (e.g. a signal glyph).

| Property | Type | Default | |
|---|---|---|---|
| `accessories` | alias | `extra.data` |  |
| `text` | string | |  |
| `subtitle` | string | |  |
| `value` | string | |  |
| `iconName` | string | |  |
| `iconSource` | url | |  |
| `chevron` | bool | `false` |  |
| `selected` | bool | `false` | trailing accent check mark (choices) |
| `busy` | bool | `false` | trailing spinner |
| `iconColor` | color | `Theme.text` |  |
| `iconTile` | real | `0` | >0: symbolic icon on a rounded colour tile of this size |
| `tileColor` | color | `Theme.accent` |  |
| `showSwitch` | bool | `false` |  |
| `checked` | alias | `toggle.checked` |  |
| `destructive` | bool | `false` |  |
| `enabled` | bool | `true` |  |
| `separator` | bool | `true` |  |
| `textColor` | color | `destructive ? Theme.danger : Theme.text` |  |

Signals: `clicked()`, `toggled(bool checked)`

### Page

Scrollable page with an astraOS large title (SettingsHome.png). Pages pushed on a PageStack get a back button automatically.

| Property | Type | Default | |
|---|---|---|---|
| `title` | string | |  |
| `showBack` | bool | `stack !== null && stack.depth > 1` |  |
| `stack` | var | `null` | set by PageStack |
| `content` | alias | `column.data` |  |
| `actions` | alias | `actionRow.data` | buttons at the right of the navigation bar |
| `spacing` | real | `18` |  |
| `centeredTitle` | bool | `false` | compact bar: back button + centred title (AboutFinal.png) |
| `background` | Component | `null` | replaces the black page background |
| `flickable` | alias | `flick` |  |

### PageStack

Navigation stack with iOS style spring transitions and an edge swipe to go back.

| Property | Type | Default | |
|---|---|---|---|
| `spring` | var (read-only) | `Motion.curve(0.42, 1.0)` |  |
| `springDuration` | int (read-only) | `Motion.duration(0.42, 1.0)` |  |

Functions: `open(component, properties)`

### ProgressBar

Rounded progress (0..1), or a sweeping bar when indeterminate.

| Property | Type | Default | |
|---|---|---|---|
| `value` | real | `0` |  |
| `indeterminate` | bool | `false` |  |
| `color` | color | `Theme.accent` |  |
| `trackColor` | color | `Theme.surfaceRaised` |  |

### SegmentedControl

A row of mutually exclusive options with a sliding pill. SegmentedControl { model: [qsTr("Day"), qsTr("Week")]; currentIndex: 0; onActivated: (i) => ... }

| Property | Type | Default | |
|---|---|---|---|
| `model` | var | `[]` |  |
| `currentIndex` | int | `0` |  |

Signals: `activated(int index)`

### ShareSheet

Share or open files with other apps. Apps list the types they accept in their app.json ("share": ["image/*"], "opens": ["text/plain"]) and receive them as launch arguments: { action: "share" | "open", files: [paths], text }. ShareSheet { id: share } share.open([path], "image/png")            // share share.open([path], "text/plain", "open")    // open with

| Property | Type | Default | |
|---|---|---|---|
| `files` | var | `[]` |  |
| `text` | string | |  |
| `mimeType` | string | `"*/*"` |  |
| `kind` | string | `"share"` |  |
| `targets` | var (read-only) | |  |

Signals: `done()`

Functions: `open(paths, mime, how, text)`, `close()`

### Sheet

A bottom sheet that springs up over a dimmed page; tap outside or drag it down to close.

| Property | Type | Default | |
|---|---|---|---|
| `content` | alias | `body.data` |  |
| `title` | string | |  |
| `maxHeight` | real | `parent ? parent.height * 0.9 : 600` |  |
| `opened` | bool (read-only) | `reveal.to > 0` |  |

Functions: `open()`, `close()`

### Slider

Horizontal slider (0..1 by default).

| Property | Type | Default | |
|---|---|---|---|
| `from` | real | `0` |  |
| `to` | real | `1` |  |
| `value` | real | `0` |  |
| `stepSize` | real | `0` |  |
| `fillColor` | color | `Theme.accent` |  |
| `position` | real (read-only) | `(value - from) / (to - from)` |  |

Signals: `moved(real value)`

### Spinner

Activity indicator: a rotating arc with rounded caps.

| Property | Type | Default | |
|---|---|---|---|
| `size` | real | `24` |  |
| `running` | bool | `true` |  |
| `color` | color | `Theme.text` |  |

### Switch

iOS style switch with a springy knob (SettingsHome.png). It does not change `checked` by itself: bind `checked` to the real state and update that state in onToggled, so the switch always tells the truth.

| Property | Type | Default | |
|---|---|---|---|
| `checked` | bool | `false` |  |
| `enabled` | bool | `true` |  |

Signals: `toggled(bool checked)`

### TabBar

The tab bar at the bottom of an app with sections (Music, Phone, Clock): an icon and a label per tab, the selected one in the app's colour. TabBar { id: tabs model: [{ icon: "play", label: qsTr("Listen Now") }, { icon: "search", label: qsTr("Search") }] onActivated: (index) => stack.currentIndex = index } It anchors itself to the bottom of its parent and leaves room for the home indicator; put the content above it (anchors.bottom: tabs.top).

| Property | Type | Default | |
|---|---|---|---|
| `model` | var | `[]` |  |
| `currentIndex` | int | `0` |  |
| `tint` | color | `Theme.accent` |  |

Signals: `activated(int index)`, `reselected(int index)` (the current tab tapped again: back to its top)

### TextField

Single line text input on a dark rounded field.

| Property | Type | Default | |
|---|---|---|---|
| `text` | alias | `input.text` |  |
| `placeholder` | string | |  |
| `echoMode` | alias | `input.echoMode` |  |
| `inputMethodHints` | alias | `input.inputMethodHints` |  |
| `maximumLength` | alias | `input.maximumLength` |  |
| `validator` | alias | `input.validator` |  |

Signals: `accepted()`

Functions: `focusInput()`

### Theme

astraOS design tokens (docs/DESIGN.md). Measurements are in logical pixels on a ~393 px wide screen (the reference size of the design concepts). Nothing in the system has a sharp corner: every surface uses one of the radii below.

| Property | Type | Default | |
|---|---|---|---|
| `fontFamily` | string (read-only) | `"Poppins"` |  |
| `accents` | var (read-only) | `[` |  |
| `accentId` | string (read-only) | |  |
| `accentEntry` | var (read-only) | `{` |  |
| `mode` | string (read-only) | `Settings.values["theme.mode"] || "dark"` |  |
| `clock` | date | `new Date()` |  |
| `ticker` | Timer | |  |
| `light` | bool (read-only) | `{` |  |
| `dark` | bool (read-only) | `!light` |  |
| `background` | color (read-only) | `light ? "#F2F2F7" : "#000000"` |  |
| `surface` | color (read-only) | `light ? "#FFFFFF" : "#151517"` |  |
| `surfaceRaised` | color (read-only) | `light ? "#E6E6EB" : "#202024"` |  |
| `surfacePressed` | color (read-only) | `light ? "#D6D6DC" : "#2A2A30"` |  |
| `separator` | color (read-only) | `light ? "#DCDCE1" : "#2A2A2E"` |  |
| `text` | color (read-only) | `light ? "#0B0B0F" : "#FFFFFF"` |  |
| `textSecondary` | color (read-only) | |  |
| `textTertiary` | color (read-only) | |  |
| `accentText` | color (read-only) | `"#FFFFFF"` | text and icons on accent colours |
| `sheet` | color (read-only) | `light ? "#FFFFFF" : "#1C1C20"` | dialogs, bottom sheets |
| `glassPanel` | color (read-only) | |  |
| `accent` | color (read-only) | `accentEntry.color` | switches, selections, primary buttons |
| `accentDeep` | color (read-only) | `accentEntry.deep` | second stop of accent gradients |
| `highlight` | color (read-only) | `"#FF0A8E"` | Control Center toggles |
| `success` | color (read-only) | `"#34D058"` |  |
| `warning` | color (read-only) | `"#FFB020"` |  |
| `danger` | color (read-only) | `"#FF453A"` |  |
| `switchOff` | color (read-only) | `light ? "#D1D1D6" : "#4A4A50"` |  |
| `glass` | color (read-only) | `Qt.rgba(0, 0, 0, 0.32)` | pills on wallpaper |
| `glassStrong` | color (read-only) | `Qt.rgba(0, 0, 0, 0.55)` |  |
| `glassButton` | color (read-only) | `Qt.rgba(0, 0, 0, 0.82)` | Control Center buttons |
| `scrim` | color (read-only) | `Qt.rgba(0, 0, 0, 0.45)` |  |
| `fontScale` | real (read-only) | |  |
| `largeTitleSize` | int (read-only) | `font(40)` |  |
| `titleSize` | int (read-only) | `font(24)` |  |
| `headlineSize` | int (read-only) | `font(17)` |  |
| `bodySize` | int (read-only) | `font(15)` |  |
| `captionSize` | int (read-only) | `font(13)` |  |
| `footnoteSize` | int (read-only) | `font(11)` |  |
| `statusBarHeight` | real (read-only) | `47` |  |
| `homeIndicatorHeight` | real (read-only) | `30` |  |
| `margin` | real (read-only) | `16` |  |
| `spacing` | real (read-only) | `10` |  |
| `rowHeight` | real (read-only) | `58` |  |
| `radiusSmall` | real (read-only) | `12` | chips, small buttons, text fields |
| `radius` | real (read-only) | `18` | list rows, tiles |
| `cardRadius` | real (read-only) | `26` | cards and groups |
| `sheetRadius` | real (read-only) | `34` | dialogs, panels, bottom sheets |
| `screenRadius` | real (read-only) | `44` | apps while they open, close or are listed in Recents |
| `iconRadiusRatio` | real (read-only) | `0.30` | app icon corner radius / size |
| `springSnappy` | real (read-only) | `5.2` |  |
| `springBouncy` | real (read-only) | `3.6` |  |
| `dampingBouncy` | real (read-only) | `0.62` |  |
| `dampingCalm` | real (read-only) | `0.86` |  |

Functions: `font(size)`

### WidgetTile

The common layout of a home screen widget: a glyph, a big title and a line of detail, sized for small / medium / large.

| Property | Type | Default | |
|---|---|---|---|
| `size` | string | `"small"` |  |
| `iconName` | string | |  |
| `iconSource` | url | |  |
| `accent` | color | `Theme.accent` |  |
| `title` | string | |  |
| `subtitle` | string | |  |
| `caption` | string | | small caps line at the top |
| `extra` | alias | `more.data` |  |

## Astra.Core

Singletons backed by the system (astrad). Calls that need a permission ask the user the first time.

### Files

File operations for apps (singleton "Files"), limited to the shared storage (/data/media/0, needs the MEDIA permission) and the app's own data directory. Paths are absolute.  Files.list(Files.home)  -> [{ name, path, url, dir, size, modified, mime, hidden }] Files.copy([a, b], dir) / Files.move(...) / Files.remove([...]) / Files.mkdir(dir, "New")

| Property | Type | |
|---|---|---|
| `home` | QString | shared storage root |
| `appData` | QString |  |

| Function | |
|---|---|
| `QString mkdir(QString dir, QString name)` | returns the new path or "" |
| `QString rename(QString path, QString name)` |  |
| `int remove(QVariantList paths)` | returns how many were removed |
| `int copy(QVariantList paths, QString dir)` |  |
| `int move(QVariantList paths, QString dir)` |  |
| `bool writeText(QString path, QString text)` |  |

### ImageTools

Image helpers for the system UI (singleton "ImageTools").

### MailClient (type)

E-mail for the Mail app: IMAP over TLS (port 993) to read, SMTP over TLS (465) or STARTTLS (587) to send. One IMAP connection, commands in order.  MailClient { id: mail } mail.configure({ imapHost, imapPort, smtpHost, smtpPort, user, password, name, address }) mail.folders(cb)                      cb([{ name, path, flags }], error) mail.messages(folder, count, cb)      newest first: [{ uid, from, subject, date, seen, flagged, attachments }] mail.message(folder, uid, cb)         { uid, from, to, cc, subject, date, text, html, attachments: [names] } mail.setFlag(folder, uid, flag, on, cb)   flag: "\\Seen" | "\\Flagged" mail.move(folder, uid, target, cb)    mail.remove(folder, uid, cb) mail.send({ to, cc, subject, text, inReplyTo }, cb)

| Property | Type | |
|---|---|---|
| `busy` | bool |  |
| `lastError` | QString |  |

| Function | |
|---|---|
| `void configure(QVariantMap account)` |  |
| `void folders(QJSValue callback)` |  |
| `void messages(QString folder, int count, QJSValue callback)` |  |
| `void message(QString folder, qint64 uid, QJSValue callback)` |  |
| `void setFlag(QString folder, qint64 uid, QString flag, bool on, QJSValue callback)` |  |
| `void move(QString folder, qint64 uid, QString target, QJSValue callback)` |  |
| `void remove(QString folder, qint64 uid, QJSValue callback)` |  |
| `void send(QVariantMap mail, QJSValue callback)` |  |
| `void disconnectFromServer()` |  |

### MediaController

The active media session as seen by the system UI (singleton).

| Property | Type | |
|---|---|---|
| `session` | QVariantMap |  |
| `active` | bool |  |

| Function | |
|---|---|
| `void command(QString action, qreal position = -1)` |  |

### MediaSession (type)

Publishes what an app is playing: MediaSession { title: player.title; artist: ...; playing: ...; onCommand: (a) => ... }

| Function | |
|---|---|
| `void setArtworkImage(QVariant image)` |  |

### Notifications

Live list of notifications (QML singleton "Notifications"). SysBoard sees everything; apps see and post their own.

| Property | Type | |
|---|---|---|
| `count` | int |  |

| Function | |
|---|---|
| `void dismiss(int id)` |  |
| `void clear()` |  |

### Packages

Installed packages (QML singleton "Packages").

| Property | Type | |
|---|---|---|
| `count` | int |  |
| `ready` | bool |  |
| `widgets` | QVariantList |  |

| Function | |
|---|---|
| `void uninstall(QString package, QJSValue callback = QJSValue())` |  |
| `void details(QString package, QJSValue callback)` |  |

### Weather

Current weather (singleton "Weather").

| Property | Type | |
|---|---|---|
| `current` | QVariantMap |  |
| `available` | bool |  |

| Function | |
|---|---|
| `void refresh()` |  |

### Application

The running app (singleton "Application"): identity, launch arguments and intents delivered while it is already running.

| Property | Type | |
|---|---|---|
| `packageName` | QString |  |
| `args` | QVariantMap |  |
| `dataDir` | QString |  |
| `mediaDir` | QString |  |
| `accent` | QColor |  |

| Function | |
|---|---|
| `void quit()` |  |
| `void mediaAsync(QStringList nameFilters, QJSValue callback)` |  |
| `bool removeMedia(QString path)` |  |

### Network

Wi-Fi, Bluetooth, mobile data, airplane mode (singleton "Network").

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Location

Where the phone is (singleton "Location"). state: { enabled, fix: { lat, lon, accuracy, source, time } }. Location.call("get", { maxAge: 30, watch: true }, cb) asks for a fresh fix; "watch" keeps it updating for a minute (needs LOCATION).

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Calendar

Events of the shared calendar (singleton "Calendar"). Calendar.call("list", { from, to }, cb); revision changes whenever an event changes (CALENDAR).

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Account

AstraID on this phone (singleton "Account", system apps). state: { signedIn, email, name, server, findMy, contactsBackup, lastBackup, lastReport }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### CloudyEngine

Cloudy's on-device model (singleton "CloudyEngine", Cloudy only). state: { models, engine, downloading, progress, running, ready, port, error }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Telephony

Calls and SMS (singleton "Telephony"). state: { calls: [...] }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Contacts

Address book (singleton "Contacts"). state: { contacts: [...] }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Alarms

Alarms and timers (singleton "Alarms"). state: { alarms, timers, next, ringing }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Display

Display modes (singleton "Display"). state: { modes, current, ... }

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Updates

Software updates (singleton "Updates").

`state` (map, the service's state), `ready`, `revision`; `call(method, params, callback(result, error))`.

### Permissions

Runtime permissions (singleton "Permissions"). Permissions.request("astra.permission.CAMERA", function(granted) { ... }) A request shows the system dialog; if the user allows it the app is restarted by the system to pick up the new group, unless `restart` is false in which case it keeps running and gains access on next launch.

| Property | Type | |
|---|---|---|
| `revision` | int |  |

| Function | |
|---|---|
| `void check(QString permission, QJSValue callback)` |  |
| `void request(QString permission, QJSValue callback = QJSValue())` |  |
| `void catalog(QJSValue callback)` |  |
| `void forPackage(QString package, QJSValue callback)` |  |
| `void apps(QString permission, QJSValue callback)` |  |

### Dialogs

Bottom sheet dialogs (singleton "Dialogs"). Dialogs.show({ title: "Delete?", message: "...", buttons: [{id: "no", label: "Cancel"}, {id: "yes", label: "Delete", style: "destructive"}] }, function(button) { ... }) The first button is the cancel action. SysBoard presents them; it also uses pending()/answer() and the shown/closed signals.

| Function | |
|---|---|
| `void show(QVariantMap dialog, QJSValue callback = QJSValue())` |  |
| `void answer(int id, QString button)` |  |
| `void pending(QJSValue callback)` |  |

### Language

UI language (singleton "Language").

| Property | Type | |
|---|---|---|
| `current` | QString |  |
| `available` | QVariantList |  |

| Function | |
|---|---|
| `void set(QString code)` |  |

### Fonts

Fonts installed in /system/fonts (singleton "Fonts").

| Property | Type | |
|---|---|---|
| `families` | QStringList |  |

### Settings

System settings (QML singleton "Settings"). Text { text: Settings.values["account.name"] } Settings.setValue("lockscreen.clock_weight", "Bold")

| Property | Type | |
|---|---|---|
| `values` | QVariantMap |  |
| `ready` | bool |  |

| Function | |
|---|---|
| `void setValue(QString key, QVariant value)` |  |
| `void reset(QString key)` |  |

### System

System state and hardware controls (QML singleton "System").

| Property | Type | |
|---|---|---|
| `connected` | bool |  |
| `info` | QVariantMap |  |
| `batteryLevel` | int |  |
| `charging` | bool |  |
| `brightness` | qreal |  |
| `torch` | bool |  |
| `torchAvailable` | bool |  |
| `battery` | QVariantMap |  |
| `version` | QString |  |

| Function | |
|---|---|
| `void setBrightness(qreal value)` |  |
| `void setTorch(bool on)` |  |
| `void power(QString action, QJSValue callback = QJSValue())` |  |
| `void setScreen(bool on)` |  |
| `void screenshot(QJSValue callback = QJSValue())` |  |
| `void markBootCompleted()` |  |
| `void call(QString method, QVariantMap params, QJSValue callback)` |  |
