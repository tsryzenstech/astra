// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// One app in a list: icon, name, summary and the GET button.
Item {
    id: row
    required property var store
    property var entry: ({})
    property int rank: 0
    width: parent ? parent.width : 300
    height: 76

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Text {
            visible: row.rank > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: row.rank
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.Bold
            color: Theme.text
        }
        AppIcon { anchors.verticalCenter: parent.verticalCenter; size: 60; source: row.entry.icon || "" }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: row.width - 60 - 12 - 96 - (row.rank > 0 ? 34 : 0)
            Text { width: parent.width; elide: Text.ElideRight; text: row.entry.name || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
            Text { width: parent.width; elide: Text.ElideRight; text: row.entry.summary || row.entry.category || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: row.store.openPage(row.entry) }
    GetButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; store: row.store; entry: row.entry }
    Rectangle { anchors.bottom: parent.bottom; x: (row.rank > 0 ? 34 : 0) + 72; width: parent.width - x; height: 1; color: Theme.separator }
}
