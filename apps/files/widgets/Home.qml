// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: the files you used last.
Item {
    id: root
    property string size: "medium"
    readonly property var recent: Files.recent(4)
    Text { text: qsTr("RECENT FILES"); font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: "#0A84FF" }
    Column {
        y: 22
        width: parent.width
        spacing: 6
        Repeater {
            model: root.recent
            delegate: Row {
                required property var modelData
                spacing: 8
                Icon { name: "file"; size: 16; anchors.verticalCenter: parent.verticalCenter }
                Text { width: root.width - 30; elide: Text.ElideMiddle; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: 13; color: "white" }
            }
        }
        Text { visible: root.recent.length === 0; text: qsTr("No recent files"); font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.6) }
    }
}
