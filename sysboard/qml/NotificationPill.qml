// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls
import Astra.Animation

// One notification. Tap opens the app, the chevron expands the full text.
Rectangle {
    id: root

    property string appName
    property url icon
    property string title
    property string body
    property date time
    property bool expanded: false
    signal openRequested()
    signal dismissRequested()

    // Swipe left or right to dismiss: the notification follows the finger
    // and fades out completely.
    Spring { id: swipe; to: 0; response: 0.32; dampingFraction: 0.86 }
    property bool dismissing: false
    transform: Translate { x: swipe.value }
    opacity: 1 - Math.min(1, Math.abs(swipe.value) / (width * 0.85))
    Connections {
        target: swipe
        function onSettled() { if (root.dismissing) root.dismissRequested() }
    }

    height: expanded ? Math.max(89, details.y + details.height + 18) : 89
    Behavior on height { SpringNumberAnimation { preset: Motion.snappy } }
    radius: expanded ? 34 : 44.5
    color: Qt.rgba(0, 0, 0, 0.45)
    clip: true

    AppIcon {
        id: art
        x: 12
        y: 17
        size: 55
        source: root.icon
        round: true
    }

    Column {
        id: texts
        x: 80
        y: 13
        width: parent.width - x - 48

        Row {
            spacing: 5
            Text {
                id: app
                text: root.appName
                font.family: Theme.fontFamily
                font.pixelSize: 21
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                anchors.baseline: app.baseline
                text: "• " + Qt.locale().toString(root.time, "HH:mm")
                font.family: Theme.fontFamily
                font.pixelSize: 14
                color: "white"
            }
        }
        Text {
            width: parent.width
            text: root.title
            wrapMode: Text.Wrap
            maximumLineCount: root.expanded ? 6 : 2
            elide: Text.ElideRight
            lineHeight: 0.92
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: "white"
        }
    }

    Column {
        id: details
        x: 80
        y: texts.y + texts.height + 8
        width: parent.width - x - 24
        spacing: 10
        visible: root.expanded
        opacity: root.expanded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Text {
            visible: root.body !== ""
            width: parent.width
            text: root.body
            wrapMode: Text.Wrap
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: Qt.rgba(1, 1, 1, 0.75)
        }
        Row {
            spacing: 8
            Repeater {
                model: [{ label: qsTr("Open"), action: "open" }, { label: qsTr("Dismiss"), action: "dismiss" }]
                delegate: Rectangle {
                    required property var modelData
                    width: label.implicitWidth + 26
                    height: 30
                    radius: 15
                    color: Qt.rgba(1, 1, 1, 0.14)
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: parent.modelData.action === "open" ? root.openRequested() : root.dismissRequested()
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: !root.dismissing
        property real startX
        property bool dragging: false
        VelocityTracker { id: velocity }
        onPressed: (m) => {
            startX = m.x
            dragging = false
            velocity.reset()
            velocity.addPoint(m.x, m.y)
        }
        onPositionChanged: (m) => {
            velocity.addPoint(m.x, m.y)
            const dx = m.x - startX
            if (!dragging && Math.abs(dx) > 12) {
                dragging = true
                preventStealing = true
            }
            if (dragging)
                swipe.value = dx
        }
        onReleased: {
            const vx = velocity.velocity().x
            const away = Math.abs(swipe.value) > root.width * 0.35 || Math.abs(vx) > 700
            if (dragging && away) {
                const side = (Math.abs(vx) > 700 ? vx : swipe.value) > 0 ? 1 : -1
                root.dismissing = true
                swipe.animateTo(side * root.width * 1.1, vx / root.width)
            } else if (dragging) {
                swipe.animateTo(0, vx / root.width)
            } else {
                root.openRequested()
            }
            dragging = false
            preventStealing = false
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 32
        name: "chevron-down"
        size: 24
        rotation: root.expanded ? 180 : 0
        Behavior on rotation { SpringNumberAnimation { preset: Motion.snappy } }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -14
            onClicked: root.expanded = !root.expanded
        }
    }
}
