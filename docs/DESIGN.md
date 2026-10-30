# The astraOS design language

astraOS has one look and one way of doing things, in every app, system or
third-party. Someone who has used one astraOS app knows how to use all of
them: where the back button is, what a list row does when tapped, how a
sheet slides up and goes away, what is a button and what is text. That is
the point of astraOS, so it is not a guideline: it is enforced.

## What every app is made of

- **Astra.Controls** for everything on screen: `Page`, `PageStack`, `ListGroup`,
  `ListItem`, `Button`, `IconButton`, `TextField`, `Switch`, `Slider`,
  `SegmentedControl`, `Sheet`, `Card`, `TabBar`, `EmptyState`, `Spinner`,
  `ProgressBar`, `Icon`, `WidgetTile` ([reference](sdk/REFERENCE.md)).
  Plain `QtQuick` items (Item, Column, Row, Text, Image, Repeater, ListView,
  Flickable, MouseArea...) arrange and fill them.
- **Theme** for colours, type and sizes: `Theme.text`, `Theme.textSecondary`,
  `Theme.background`, `Theme.surface`, `Theme.separator`, `Theme.accent`,
  `Theme.fontFamily`, `Theme.bodySize`, `Theme.titleSize`, `Theme.captionSize`...
  Theme follows the user: light or dark, their accent colour, their text
  size. An app that hard-codes a colour breaks in the other mode.
- **One colour of its own.** An app may declare `"accent": "#RRGGBB"` in
  `app.json` (WhatsAstra's green, Tune's red) and use it through
  `Application.accent`. Nothing else.
- **The system's motion.** `PageStack` pushes with springs, `Sheet` slides
  up, lists scroll with the system's physics; `Astra.Animation` (Spring)
  for anything custom.
- **The system font**, translated text (`qsTr()`), and the system's window:
  an app is a `Page`, a `PageStack` or an `Item`, never a `Window`.

## Native, not web

Third-party apps are native astraOS apps. A web page in a frame does not
follow the user's theme, text size or gestures, so `QtWebEngine` /
`WebEngineView` are for the system's browser (Planet) and the system apps
built into the image, not for apps. Services that only have a website get a
native client built with the SDK (see WhatsAstra).

## The rules `astra check` enforces

| Code | Rule |
|---|---|
| E010 | No `QtQuick.Controls`, `QtQuick.Dialogs`, `QtQuick.Templates`, `QtQuick.Window`, `Qt5Compat.GraphicalEffects`: Astra.Controls replaces them |
| E011 | No `QtWebEngine` / `QtWebView` / `QtWebChannel` in third-party apps |
| E012 | Only the SDK's modules: `QtQuick`, `QtQml`, `QtQml.Models`, `QtQuick.Layouts`, `QtQuick.Shapes`, `QtQuick.Effects`, `QtMultimedia`, `QtPositioning`, `QtSensors`, `Astra.Core`, `Astra.Controls`, `Astra.Animation`, and the app's own files |
| E020 | No `Window`, `ApplicationWindow`, `FontLoader`, `WebEngineView`, `WebView` |
| E030 | `font.family` is `Theme.fontFamily` |
| E040 | No colour literals (`"#..."`, `Qt.rgba()`...) in colour properties, except the app's `accent` |
| E100, E101 | A valid `app.json` (see [APKG.md](APKG.md)); `accent` is `#RRGGBB` |
| W050 | Sizes from Theme rather than numbers (`font.pixelSize: Theme.bodySize`) |
| W060 | Visible text goes through `qsTr()` |

Errors stop `astra build` and Astra Studio from packaging the app, and
Market from publishing it. Only the apps built into the system image are
checked with the system's exceptions (web engine for Planet, the lock
screen's font previews).
