// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// GET / UPDATE / OPEN pill, with a spinner while the app installs.
Rectangle {
    id: root
    required property var store
    property var entry: ({})
    property bool prominent: false
    readonly property int have: store.installedVersion(entry.package)
    readonly property bool busy: !!store.installing[entry.package]
    readonly property bool update: have > 0 && (entry.versionCode || 1) > have
    readonly property string label: busy ? "" : have === 0 ? qsTr("GET") : update ? qsTr("UPDATE") : qsTr("OPEN")

    width: busy ? height : Math.max(prominent ? 96 : 74, text.implicitWidth + 32)
    height: prominent ? 34 : 30
    radius: height / 2
    color: prominent || have === 0 || update ? Theme.accent : Theme.surfaceRaised
    Behavior on width { SpringNumberAnimation { preset: Motion.snappy } }
    scale: area.pressed ? 0.94 : 1
    Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: 14
        font.weight: Font.Bold
        color: root.color === Theme.accent ? "white" : Theme.accent
    }
    Spinner { anchors.centerIn: parent; visible: root.busy; width: 20; height: 20 }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -6
        enabled: !root.busy
        onClicked: root.have > 0 && !root.update ? Packages.launch(root.entry.package) : root.store.install(root.entry)
    }
}
