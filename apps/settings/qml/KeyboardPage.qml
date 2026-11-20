// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Keyboard (astraOS Desktop): the layout of the keyboard. It applies at once to the system and to every app
// (SysBoard gives them the keymap, sysboard/xkbkeyboard.cpp).
Page {
    id: page
    title: qsTr("Keyboard")

    // code (xkb layout) or "layout:variant"; the names are in the language of the keyboard.
    readonly property var layouts: [
        { code: "us", name: "English (US)" },
        { code: "us:intl", name: "English (US, international)" },
        { code: "gb", name: "English (UK)" },
        { code: "it", name: "Italiano" },
        { code: "de", name: "Deutsch" },
        { code: "ch", name: "Deutsch (Schweiz)" },
        { code: "fr", name: "Français" },
        { code: "es", name: "Español" },
        { code: "latam", name: "Español (Latinoamérica)" },
        { code: "pt", name: "Português" },
        { code: "br", name: "Português (Brasil)" },
        { code: "nl", name: "Nederlands" },
        { code: "se", name: "Svenska" },
        { code: "no", name: "Norsk" },
        { code: "dk", name: "Dansk" },
        { code: "fi", name: "Suomi" },
        { code: "pl", name: "Polski" },
        { code: "cz", name: "Čeština" },
        { code: "ru", name: "Русский" },
        { code: "ua", name: "Українська" },
        { code: "gr", name: "Ελληνικά" },
        { code: "tr", name: "Türkçe" },
        { code: "jp", name: "日本語" }
    ]
    readonly property string current: Settings.values["desktop.keyboard.layout"] || "us"

    ListGroup {
        title: qsTr("Try it")
        TextField {
            width: parent.width - 24
            x: 12
            height: 44
            placeholder: qsTr("Type here to try the layout")
        }
        Item { width: 1; height: 10 }
    }

    ListGroup {
        title: qsTr("Layout")
        footer: qsTr("The layout of the keyboard of this computer. It applies to every app.")
        Repeater {
            model: page.layouts
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                selected: modelData.code === page.current
                separator: index < page.layouts.length - 1
                onClicked: Settings.setValue("desktop.keyboard.layout", modelData.code)
            }
        }
    }
}
