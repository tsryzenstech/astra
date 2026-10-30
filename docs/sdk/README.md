# astraOS SDK

Everything needed to make an astraOS app: project templates, the components
of the system UI, the design language check, packaging, and running on a
phone. [Astra Studio](https://github.com/tsryzenstech/astra-studio) is the IDE
built on it (Windows); the same tools work from the command line on Windows,
Linux and macOS.

- [Getting started](#getting-started)
- [The design language](../DESIGN.md): what `astra check` enforces
- [API reference](REFERENCE.md): Astra.Controls and Astra.Core
- [Writing apps](../APPS.md), [the .apkg format](../APKG.md)

## Getting started

You need Python 3. In this repository the SDK is `sdk/` (Astra Studio ships
its own copy):

```bash
sdk/bin/astra new myapp --template list --name "My App" --package com.example.myapp
sdk/bin/astra check myapp
sdk/bin/astra run myapp
```

On Windows use `sdk\bin\astra.cmd`. `astra run` packages the app, installs it
on the phone connected over USB (Settings > Developer options > USB
debugging) and follows its log.

| Command | |
|---|---|
| `astra new <dir> [--template app\|tabs\|list] [--name] [--package] [--accent #RRGGBB]` | a new project |
| `astra templates` | the templates |
| `astra check [dir] [--json]` | the design language and the manifest; `--json` for tools |
| `astra build [dir] [-o file.apkg]` | check, then package (`dist/<package>.apkg`) |
| `astra run [dir]` | build, install on the phone, start, follow the log |
| `astra install <app.apkg>`, `astra logs`, `astra screenshot [file]`, `astra devices` | the phone |
| `astra i18n [dir]` | add new `qsTr()` strings to `i18n/<language>.json` |

## A project

```
myapp/
├── app.json          manifest: package, name, version, accent, permissions, widgets
├── icon.svg
├── qml/Main.qml      the app: a Page, a PageStack or an Item
├── widgets/          home and lock screen widgets (optional)
└── i18n/it.json      translations (astra i18n)
```

```qml
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    title: qsTr("Hello")
    ListGroup {
        ListItem {
            text: qsTr("Post a notification")
            chevron: true
            onClicked: Notifications.post(qsTr("Hello"), qsTr("From my app"))
        }
    }
}
```

The templates:

| Template | |
|---|---|
| `app` | one page with a list, a card and a sheet |
| `tabs` | sections behind a `TabBar`, each with its own `PageStack` |
| `list` | items saved in the app's data folder (`Files.appData`), a detail page, a sheet to add one |

## Talking to a server

An app that needs a backend (a chat service, a sync API) does not ship its
own credentials: it calls its API on the astraOS cloud server through the
phone's AstraID session, which the app never sees. The path must be under
`/api/app/<the app's package>/`; the app needs `astra.permission.INTERNET`.

```qml
Account.call("request", { method: "POST", path: "/api/app/com.example.chat/send",
                          body: { to: chatId, text: message } },
             (reply, error) => {
    if (error)                       // offline, or not signed in to AstraID
        return console.warn(error)
    console.log(reply.status, JSON.stringify(reply.body))   // body: JSON, or text
})
```

Methods are `GET`, `POST`, `PUT` and `DELETE`. The server side is a set of
routes in astra-cloud under the same prefix; WhatsAstra (`lib/whatsapp.js`,
backed by OpenWA) is the example.

## Publishing

Upload the `.apkg` from `astra build` in the developer panel of the store
(`/dev/` on the astraOS cloud server) or with `curl` from CI (see the server's
README). Run `astra check` first: the design check is what astraOS apps are
held to (in this repository the `sdk` workflow runs it on every system app).

## Updating the reference

`docs/sdk/REFERENCE.md` is generated from the sources:

```bash
python3 sdk/tools/gen_reference.py
```
