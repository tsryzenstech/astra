// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Add a widget (the "+" while editing the home screen): every widget of
// every app, at the sizes it offers, plus the system ones.
Item {
    id: root
    property Item blurSource
    signal add(string key, string size)

    readonly property var system: [
        { key: "system/greeting", name: qsTr("Weather Greeting"), app: qsTr("System"), home: ["medium"] },
        { key: "system/search", name: qsTr("Web Search"), app: "Planet", home: ["bar"] }
    ]
    readonly property var available: system.concat((Packages.count >= 0 ? Packages.widgets : []).filter(w => w.home && w.home.length)
        .map(w => ({ key: w.key, name: w.name, app: (Packages.get(w.package) || {}).name || w.package, icon: (Packages.get(w.package) || {}).iconUrl, home: w.home })))
    property var chosen: null
    property string chosenSize: ""

    function open() { chosen = null; reveal.animateTo(1, 0) }
    function close() { reveal.animateTo(0, 0) }

    visible: reveal.value > 0.01
    Spring { id: reveal; to: 0; response: 0.44; dampingFraction: 0.8 }

    BlurLayer { anchors.fill: parent; source: root.blurSource; amount: Math.min(1, reveal.value); dim: 0.45 }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        width: parent.width
        height: parent.height * 0.82
        y: parent.height - height * reveal.value
        radius: Theme.sheetRadius
        color: Qt.rgba(0.11, 0.11, 0.13, 0.96)
        MouseArea { anchors.fill: parent }

        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 8; width: 38; height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.3) }
        Text {
            x: 22; y: 26
            text: root.chosen ? root.chosen.name : qsTr("Widgets")
            font.family: Theme.fontFamily
            font.pixelSize: 26
            font.weight: Font.Bold
            color: "white"
        }
        Text {
            visible: root.chosen !== null
            anchors.right: parent.right
            anchors.rightMargin: 22
            y: 34
            text: qsTr("Back")
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.chosen = null }
        }

        // The list of widgets
        ListView {
            visible: root.chosen === null
            x: 16
            y: 80
            width: parent.width - 32
            height: parent.height - 100
            clip: true
            spacing: 8
            model: root.available
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: 64
                radius: 18
                color: Qt.rgba(1, 1, 1, 0.08)
                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    AppIcon { size: 40; source: modelData.icon || ""; visible: !!modelData.icon; anchors.verticalCenter: parent.verticalCenter }
                    Icon { visible: !modelData.icon; name: "sparkles"; size: 30; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.DemiBold; color: "white" }
                        Text { text: modelData.app; font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.6) }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.chosen = modelData
                        root.chosenSize = modelData.home[0]
                    }
                }
            }
        }

        // Size picker with a live preview
        Column {
            visible: root.chosen !== null
            anchors.horizontalCenter: parent.horizontalCenter
            y: 90
            width: parent.width - 44
            spacing: 22
            Item {
                width: parent.width
                height: 300
                HomeWidget {
                    readonly property var dims: ({ small: [150, 150], medium: [parent.width, 150], large: [parent.width, 300], bar: [parent.width, 46] })[root.chosenSize] || [150, 150]
                    anchors.centerIn: parent
                    width: dims[0]
                    height: dims[1]
                    widgetKey: root.chosen ? root.chosen.key : ""
                    size: root.chosenSize
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                Repeater {
                    model: root.chosen ? root.chosen.home : []
                    delegate: Rectangle {
                        required property string modelData
                        width: 12; height: 12; radius: 6
                        color: root.chosenSize === modelData ? "white" : Qt.rgba(1, 1, 1, 0.3)
                        MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: root.chosenSize = parent.modelData }
                    }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: ({ small: qsTr("Small"), medium: qsTr("Medium"), large: qsTr("Large"), bar: qsTr("Bar") })[root.chosenSize] || ""
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: Qt.rgba(1, 1, 1, 0.7)
            }
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 220
                text: qsTr("Add Widget")
                onClicked: {
                    root.add(root.chosen.key, root.chosenSize)
                    root.close()
                }
            }
        }
    }
}
