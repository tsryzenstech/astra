// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Themes: ready-made looks (accent + wallpaper), wallpapers and accents.
Rectangle {
    id: app
    color: Theme.background

    readonly property var wallpapers: System.files("/system/media/wallpapers", ["*.png", "*.jpg"])
    readonly property string currentWallpaper: Settings.values["display.wallpaper"]
                                               || System.property("ro.system.wallpaper", "/system/media/wallpapers/default_wallpaper.png")
    readonly property var presets: [
        { name: "astra Default", accent: "orange", wallpaper: "/system/media/wallpapers/default_wallpaper.png" },
        { name: "Aurora", accent: "violet", wallpaper: "/system/media/wallpapers/aurora.jpg" },
        { name: "Sunset", accent: "pink", wallpaper: "/system/media/wallpapers/sunset.jpg" },
        { name: "Ocean", accent: "blue", wallpaper: "/system/media/wallpapers/ocean.jpg" },
        { name: "Bloom", accent: "red", wallpaper: "/system/media/wallpapers/bloom.jpg" },
        { name: "Mint", accent: "green", wallpaper: "/system/media/wallpapers/mint.jpg" }
    ]
    function apply(p) {
        Settings.setValue("theme.name", p.name)
        Settings.setValue("theme.accent", p.accent)
        Settings.setValue("display.wallpaper", p.wallpaper)
    }

    component Thumb: Item {
        id: thumb
        property string path
        property real r: 20
        Image {
            id: img
            anchors.fill: parent
            source: thumb.path ? System.fileUrl(thumb.path) : ""
            sourceSize.width: 240
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle { id: mask; anchors.fill: parent; radius: thumb.r; visible: false; layer.enabled: true }
        MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }

    Page {
        anchors.fill: parent
        title: qsTr("Themes")

        Text { text: qsTr("Featured"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize + 2; font.weight: Font.DemiBold; color: Theme.text }
        ListView {
            width: parent.width
            height: 330
            orientation: ListView.Horizontal
            spacing: 14
            clip: true
            model: app.presets
            delegate: Column {
                id: preset
                required property var modelData
                readonly property bool current: (Settings.values["theme.name"] || "astra Default") === modelData.name
                spacing: 8
                width: 150
                Item {
                    width: 150
                    height: 290
                    scale: area.pressed ? 0.96 : 1
                    Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                    Thumb { anchors.fill: parent; path: preset.modelData.wallpaper; r: 26 }
                    // A tiny home screen on top of the wallpaper
                    Grid {
                        anchors.centerIn: parent
                        columns: 3
                        spacing: 12
                        Repeater {
                            model: 6
                            Rectangle {
                                width: 28; height: 28; radius: 9
                                color: index === 0 ? Theme.accents.find(a => a.id === preset.modelData.accent).color : Qt.rgba(1, 1, 1, 0.35)
                                required property int index
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 26
                        color: "transparent"
                        border.width: preset.current ? 3 : 0
                        border.color: Theme.accent
                    }
                    MouseArea { id: area; anchors.fill: parent; onClicked: app.apply(preset.modelData) }
                }
                Text { text: preset.modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.Medium; color: Theme.text }
            }
        }

        ListGroup {
            title: qsTr("Accent colour")
            Item {
                width: parent.width
                height: 80
                Row {
                    anchors.centerIn: parent
                    spacing: 10
                    Repeater {
                        model: Theme.accents
                        delegate: Rectangle {
                            required property var modelData
                            width: 38; height: 38; radius: 19
                            gradient: Gradient { GradientStop { position: 0; color: modelData.color } GradientStop { position: 1; color: modelData.deep } }
                            border.width: modelData.id === Theme.accentId ? 3 : 0
                            border.color: "white"
                            scale: modelData.id === Theme.accentId ? 1.12 : 1
                            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                            MouseArea { anchors.fill: parent; onClicked: Settings.setValue("theme.accent", modelData.id) }
                        }
                    }
                }
            }
        }

        Text { text: qsTr("Wallpapers"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize + 2; font.weight: Font.DemiBold; color: Theme.text }
        Grid {
            columns: 3
            spacing: 10
            readonly property real cell: (parent.width - 20) / 3
            Repeater {
                model: app.wallpapers
                delegate: Item {
                    required property string modelData
                    width: parent.cell
                    height: parent.cell * 2
                    Thumb { anchors.fill: parent; path: modelData; r: 18 }
                    Rectangle { anchors.fill: parent; radius: 18; color: "transparent"; border.width: modelData === app.currentWallpaper ? 3 : 0; border.color: Theme.accent }
                    MouseArea { anchors.fill: parent; onClicked: Settings.setValue("display.wallpaper", modelData) }
                }
            }
        }

        ListGroup {
            ListItem {
                text: qsTr("Lock screen clock")
                subtitle: qsTr("Fonts and widgets")
                chevron: true
                separator: false
                onClicked: Packages.launch("com.astra.settings", { page: "lockscreen" })
            }
        }
    }
}
