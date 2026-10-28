// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Themes: the current look and the Themes app.
Page {
    id: page
    title: qsTr("Themes")

    readonly property var themesApp: Packages.count >= 0 ? Packages.get("com.astra.themes") : ({})

    Card {
        accented: true
        Column {
            width: parent.width
            spacing: 6
            Text {
                text: qsTr("Current theme")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                color: Qt.rgba(1, 1, 1, 0.85)
            }
            Text {
                text: Settings.values["theme.name"] || qsTr("astra Default")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                text: qsTr("Accent: %1").arg(qsTr(Theme.accentEntry.name))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: "white"
            }
        }
    }

    ListGroup {
        ListItem {
            text: qsTr("Open Themes")
            subtitle: qsTr("Browse themes, icon styles and wallpapers.")
            iconSource: page.themesApp.iconUrl || ""
            chevron: true
            onClicked: Packages.launch("com.astra.themes")
        }
        ListItem {
            text: qsTr("Accent colour and wallpaper")
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("GeneralPage.qml"))
        }
    }
}
