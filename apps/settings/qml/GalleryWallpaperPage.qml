// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls

// Settings > General > Wallpaper > Choose from Gallery: the pictures of the phone; touch one to make it
// the wallpaper (the lock screens that use "Default" follow it).
Page {
    id: page
    title: qsTr("Choose from Gallery")

    property var pictures: []
    property bool granted: false
    property bool checked: false
    readonly property string current: Settings.values["display.wallpaper"] || ""

    Component.onCompleted: Permissions.check("astra.permission.MEDIA", function(ok) {
        page.granted = !!ok
        page.checked = true
        if (ok)
            page.load()
    })
    function load() {
        Application.mediaAsync(["*.jpg", "*.jpeg", "*.png", "*.webp"], function(list) { page.pictures = list })
    }

    EmptyState {
        visible: page.checked && page.pictures.length === 0
        width: parent.width
        iconName: "image"
        title: qsTr("No pictures yet")
        message: qsTr("Photos and screenshots you take show up here.")
    }

    Flow {
        width: parent.width
        spacing: 8
        Repeater {
            model: page.pictures
            delegate: Item {
                id: cell
                required property var modelData
                readonly property bool on: modelData.path === page.current
                width: (page.width - 16 - 16) / 3
                height: width * 1.7
                Image {
                    id: img
                    anchors.fill: parent
                    source: cell.modelData.url
                    sourceSize.width: 240
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle { id: mask; anchors.fill: parent; radius: 14; visible: false; layer.enabled: true }
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
                    radius: 14
                    color: "transparent"
                    border.width: cell.on ? 3 : 0
                    border.color: Theme.accent
                }
                MouseArea { anchors.fill: parent; onClicked: Settings.setValue("display.wallpaper", cell.modelData.path) }
            }
        }
    }
}
