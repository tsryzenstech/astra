// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: your favourite people.
Item {
    id: root
    property string size: "small"
    readonly property var favs: (Contacts.state.contacts || []).filter(c => c.favorite).slice(0, root.size === "small" ? 4 : 4)
    Grid {
        anchors.centerIn: parent
        columns: root.size === "small" ? 2 : 4
        spacing: 12
        Repeater {
            model: root.favs
            delegate: Column {
                required property var modelData
                spacing: 4
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 46; height: 46; radius: 23
                    color: "#5A5A66"
                    Text { anchors.centerIn: parent; text: (modelData.name || "?").charAt(0).toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 20; font.weight: Font.DemiBold; color: "white" }
                    MouseArea { anchors.fill: parent; onClicked: if (modelData.phone) Packages.launch("com.astra.phone", { dial: modelData.phone }) }
                }
                Text { visible: root.size !== "small"; anchors.horizontalCenter: parent.horizontalCenter; text: (modelData.name || "").split(" ")[0]; font.family: Theme.fontFamily; font.pixelSize: 11; color: "white" }
            }
        }
    }
    Text { visible: root.favs.length === 0; anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: qsTr("Add favourites in Contacts"); font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.7) }
}
