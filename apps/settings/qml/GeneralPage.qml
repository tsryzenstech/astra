// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Settings > General Customization: accent colour, wallpaper, home screen.
Page {
    id: page
    title: qsTr("General Customization")

    readonly property var wallpapers: System.files("/system/media/wallpapers", ["*.png", "*.jpg"])
    readonly property string currentWallpaper: Settings.values["display.wallpaper"]
                                               || System.property("ro.system.wallpaper", "/system/media/wallpapers/default_wallpaper.png")

    ListGroup {
        title: qsTr("Accent colour")
        footer: qsTr("Used by switches, buttons and highlights everywhere.")
        Item {
            width: parent.width
            height: 86
            Row {
                anchors.centerIn: parent
                spacing: 10
                Repeater {
                    model: Theme.accents
                    delegate: Item {
                        required property var modelData
                        readonly property bool current: modelData.id === Theme.accentId
                        width: 38
                        height: 38
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            gradient: Gradient {
                                GradientStop { position: 0; color: modelData.color }
                                GradientStop { position: 1; color: modelData.deep }
                            }
                            scale: current ? 1.12 : 1
                            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                        }
                        Rectangle {
                            visible: current
                            anchors.fill: parent
                            anchors.margins: -5
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.text
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Settings.setValue("theme.accent", modelData.id) }
                    }
                }
            }
        }
    }

    ListGroup {
        title: qsTr("Wallpaper")
        Item {
            width: parent.width
            height: 232
            ListView {
                anchors.fill: parent
                anchors.margins: 14
                orientation: ListView.Horizontal
                spacing: 12
                clip: true
                model: page.wallpapers
                delegate: Item {
                    id: thumb
                    required property string modelData
                    readonly property bool current: modelData === page.currentWallpaper
                    width: 92
                    height: 204
                    Image {
                        id: img
                        anchors.fill: parent
                        source: System.fileUrl(thumb.modelData)
                        sourceSize.width: 184
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    Rectangle { id: mask; anchors.fill: parent; radius: 18; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        source: img
                        maskEnabled: true
                        maskSource: mask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 18
                        color: "transparent"
                        border.width: thumb.current ? 3 : 0
                        border.color: Theme.accent
                    }
                    MouseArea { anchors.fill: parent; onClicked: Settings.setValue("display.wallpaper", thumb.modelData) }
                }
            }
        }
    }

    ListGroup {
        title: qsTr("Home screen")
        ListItem {
            text: qsTr("Reset home screen layout")
            subtitle: qsTr("Puts every app back where it was when you got the phone.")
            textColor: Theme.accent
            separator: false
            onClicked: Settings.reset("home.layout")
        }
    }
}
