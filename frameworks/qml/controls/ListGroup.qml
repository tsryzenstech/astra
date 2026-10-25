// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Rounded card that stacks ListItems with hairline separators.
Rectangle {
    id: root

    default property alias content: column.data
    property string title // optional section label shown above the card

    width: parent ? parent.width : implicitWidth
    implicitHeight: column.implicitHeight + (title ? header.height + 12 : 0)
    color: "transparent"

    Text {
        id: header
        visible: root.title !== ""
        text: root.title
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        font.weight: Font.Medium
        color: Qt.rgba(1, 1, 1, 0.85)
    }

    Rectangle {
        y: root.title ? header.height + 12 : 0
        width: parent.width
        height: column.implicitHeight
        radius: Theme.cardRadius
        color: Theme.surface
        clip: true

        Column {
            id: column
            width: parent.width
        }
    }
}
