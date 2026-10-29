// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// A bottom sheet that springs up over a dimmed page; tap outside or drag
// it down to close.
Item {
    id: sheet
    default property alias content: body.data
    property string title
    property real maxHeight: parent ? parent.height * 0.9 : 600
    readonly property bool opened: reveal.to > 0
    anchors.fill: parent
    visible: reveal.value > 0.01
    z: 50

    function open() { reveal.animateTo(1, 0) }
    function close() { reveal.animateTo(0, 0) }

    Spring { id: reveal; to: 0; response: 0.4; dampingFraction: 0.84 }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4 * Math.min(1, reveal.value)
        MouseArea { anchors.fill: parent; onClicked: sheet.close() }
    }
    Rectangle {
        id: panel
        width: parent.width
        height: Math.min(sheet.maxHeight, body.childrenRect.height + header.height + 34 + Theme.homeIndicatorHeight)
        y: parent.height - height * reveal.value + Math.max(0, drag.offset)
        radius: Theme.sheetRadius
        color: Theme.sheet
        MouseArea { anchors.fill: parent }   // keeps taps inside the sheet

        Item {
            id: header
            width: parent.width
            height: sheet.title ? 58 : 22
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 38
                height: 5
                radius: 2.5
                color: Theme.separator
            }
            Text {
                visible: sheet.title !== ""
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 6
                text: sheet.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.DemiBold
                color: Theme.text
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                property real startY
                property real offset: 0
                onPressed: (m) => startY = m.y
                onPositionChanged: (m) => offset = m.y - startY
                onReleased: {
                    if (offset > 70)
                        sheet.close()
                    offset = 0
                }
            }
        }
        Flickable {
            anchors.top: header.bottom
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.homeIndicatorHeight
            width: parent.width
            contentHeight: body.childrenRect.height + 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Item {
                id: body
                x: 16
                width: parent.width - 32
                height: childrenRect.height
            }
        }
    }
}
