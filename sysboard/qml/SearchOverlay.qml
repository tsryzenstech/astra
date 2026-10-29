// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// App search, opened from the "Search" pill on the home screen.
Item {
    id: root

    property Item blurSource
    property string query: ""
    signal launchRequested(string pkg)

    readonly property var results: {
        const q = query.trim().toLowerCase()
        return Packages.count >= 0
            ? Packages.list().filter(p => p.launcher && (q === "" || p.name.toLowerCase().includes(q)))
            : []
    }

    function open() {
        query = ""
        field.text = ""
        reveal.animateTo(1, 0)
        field.focusInput()
    }
    function close() {
        reveal.animateTo(0, 0)
        Qt.inputMethod.hide()
    }

    visible: reveal.value > 0.01
    // The app list rises from the bottom with a little bounce.
    Spring { id: reveal; to: 0; response: 0.46; dampingFraction: 0.74 }

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: reveal.value
        dim: 0.4
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Item {
        width: parent.width
        height: parent.height
        opacity: Math.min(1, reveal.value * 1.8)
        y: (1 - reveal.value) * root.height * 0.75

        Row {
            id: bar
            x: 20
            y: Theme.statusBarHeight + 16
            spacing: 12
            TextField {
                id: field
                width: root.width - 40 - cancel.width - 12
                height: 44
                radius: 22
                color: Qt.rgba(0, 0, 0, 0.4)
                placeholder: qsTr("Search apps")
                onTextChanged: root.query = text
                onAccepted: if (root.results.length) { root.launchRequested(root.results[0].package); root.close() }
            }
            Text {
                id: cancel
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Cancel")
                font.family: Theme.fontFamily
                font.pixelSize: 15
                color: "white"
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.close() }
            }
        }

        GridView {
            x: 10
            y: bar.y + 70
            width: root.width - 20
            height: root.height - y - 40
            cellWidth: width / 4
            cellHeight: 106
            clip: true
            model: root.results
            delegate: Item {
                required property var modelData
                width: GridView.view.cellWidth
                height: 106
                HomeIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconSize: 62
                    source: modelData.iconUrl
                    label: modelData.name
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.launchRequested(modelData.package)
                        root.close()
                    }
                }
            }
        }
    }
}
