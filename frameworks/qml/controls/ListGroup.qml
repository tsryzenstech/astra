// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Rounded card that stacks ListItems with hairline separators.
Rectangle {
    id: root

    default property alias content: column.data
    property string title  // optional section label shown above the card
    property string footer // optional explanation shown below the card

    width: parent ? parent.width : implicitWidth
    implicitHeight: column.implicitHeight + (title ? header.height + 12 : 0) + (footer ? footerText.implicitHeight + 10 : 0)
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
        color: Theme.textSecondary
    }

    Rectangle {
        y: root.title ? header.height + 12 : 0
        width: parent.width
        height: column.implicitHeight
        radius: Theme.cardRadius
        color: Theme.surface

        Column {
            id: column
            width: parent.width
        }
    }

    Text {
        id: footerText
        visible: root.footer !== ""
        y: (root.title ? header.height + 12 : 0) + column.implicitHeight + 10
        x: 14
        width: parent.width - 28
        text: root.footer
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.footnoteSize + 1
        color: Theme.textTertiary
    }
}
