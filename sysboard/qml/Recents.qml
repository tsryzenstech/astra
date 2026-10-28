// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Apps running in the background, one card per app (its last screen).
// Opened by swiping up from the home indicator and holding still. Swipe
// sideways to browse, tap a card to go back to it, swipe a card up to close
// the app, "Close all" closes every app, tap the background to go home.
Item {
    id: root

    property var shell
    property var apps            // the AppLayer
    property Item blurSource
    property bool shown: false
    property var cards: []

    readonly property real cardWidth: Math.round(width * 0.64)
    readonly property real cardHeight: Math.round(cardWidth * height / Math.max(1, width))
    readonly property real cardRadius: Theme.screenRadius * cardWidth / Math.max(1, width) + 6
    readonly property real cardY: Math.round((height - cardHeight) / 2) - 10

    visible: reveal.value > 0.005
    Spring { id: reveal; to: 0; response: 0.4; dampingFraction: 0.86 }

    function open() {
        cards = apps.recents()
        list.positionViewAtBeginning()
        list.contentX = list.originX
        shown = true
        reveal.animateTo(1, 0)
    }
    function close() {
        shown = false
        reveal.animateTo(0, 0)
    }
    // Screen rect of the first card, where the current app shrinks to.
    function firstCardRect() {
        return Qt.rect((width - cardWidth) / 2, cardY, cardWidth, cardHeight)
    }
    function refresh() {
        cards = apps.recents()
        if (cards.length === 0)
            close()
    }

    Connections {
        target: root.apps
        function onRevisionChanged() { if (root.shown) root.refresh() }
    }

    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: reveal.value
        dim: 0.45
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        onClicked: root.close()
    }

    EmptyState {
        anchors.centerIn: parent
        width: parent.width - 80
        visible: root.cards.length === 0
        opacity: reveal.value
        iconName: "recents"
        title: qsTr("No recent apps")
        message: qsTr("Apps you open stay here while they run in the background.")
    }

    // Only the band with the cards scrolls; taps above and below go home.
    ListView {
        id: list
        y: root.cardY - 56
        width: parent.width
        height: root.cardHeight + 56
        orientation: ListView.Horizontal
        model: root.cards
        spacing: 18
        interactive: root.shown
        opacity: Math.min(1, reveal.value * 1.6)
        leftMargin: (width - root.cardWidth) / 2
        rightMargin: leftMargin
        snapMode: ListView.SnapToItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (width - root.cardWidth) / 2
        preferredHighlightEnd: preferredHighlightBegin + root.cardWidth
        flickDeceleration: 2400
        boundsBehavior: Flickable.DragOverBounds

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property var win: modelData
            width: root.cardWidth
            height: list.height
            // Hidden while its window morphs to or from it.
            opacity: win && win.morphing ? 0 : 1

            // Distance from the centre: neighbours shrink a little.
            readonly property real offset: (x - list.contentX - list.leftMargin) / (root.cardWidth + list.spacing)
            scale: 1 - Math.min(0.08, Math.abs(offset) * 0.08)

            Spring { id: lift; to: 0; response: 0.34; dampingFraction: 0.8 }
            property bool closing: false

            Row {
                y: 12 + lift.value
                x: 6
                spacing: 10
                opacity: 1 - Math.min(1, -lift.value / 200)
                AppIcon { size: 30; source: card.win ? card.win.info.iconUrl || "" : ""; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.win ? card.win.info.name || card.win.packageName : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.weight: Font.DemiBold
                    color: "white"
                }
            }

            Rectangle {
                id: face
                y: 56 + lift.value
                width: parent.width
                height: root.cardHeight
                radius: root.cardRadius
                color: card.win ? card.win.info.background || "#000000" : "black"
                opacity: 1 - Math.min(1, -lift.value / 400)

                AppIcon {
                    anchors.centerIn: parent
                    size: 72
                    visible: shot.status !== Image.Ready
                    source: card.win ? card.win.info.iconUrl || "" : ""
                }
                Image {
                    id: shot
                    anchors.fill: parent
                    source: card.win ? card.win.snapshot : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: shotMask
                    anchors.fill: parent
                    radius: root.cardRadius
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    visible: shot.status === Image.Ready
                    source: shot
                    maskEnabled: true
                    maskSource: shotMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
            }

            MouseArea {
                anchors.fill: face
                anchors.topMargin: -50
                enabled: root.shown && !card.closing
                preventStealing: dragging
                property point start
                property bool dragging: false
                VelocityTracker { id: velocity }
                onPressed: (m) => {
                    start = Qt.point(m.x, m.y)
                    dragging = false
                    velocity.reset()
                    velocity.addPoint(m.x, m.y)
                }
                onPositionChanged: (m) => {
                    velocity.addPoint(m.x, m.y)
                    const dy = m.y - start.y
                    if (!dragging && dy < -12 && Math.abs(dy) > Math.abs(m.x - start.x))
                        dragging = true
                    if (dragging)
                        lift.value = Math.min(0, dy) + Math.max(0, dy) * 0.2
                }
                onReleased: (m) => {
                    const v = velocity.velocity()
                    if (dragging) {
                        if (lift.value < -root.cardHeight * 0.3 || v.y < -900) {
                            card.closing = true
                            lift.animateTo(-root.height, v.y / root.height)
                            closeTimer.start()
                        } else {
                            lift.animateTo(0, v.y / root.height)
                        }
                    } else if (Math.hypot(m.x - start.x, m.y - start.y) < 12) {
                        const r = face.mapToItem(root, 0, 0, face.width * card.scale, face.height * card.scale)
                        const pkg = card.win.packageName
                        root.close()
                        root.apps.resume(pkg, Qt.rect(r.x, r.y, face.width * card.scale, face.height * card.scale),
                                         root.cardRadius * card.scale)
                    }
                    dragging = false
                }
            }
            Timer {
                id: closeTimer
                interval: 220
                onTriggered: root.apps.stop(card.win.packageName)
            }
        }
    }

    // Close all
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.cardY + root.cardHeight + 34 + (1 - reveal.value) * 40
        visible: root.cards.length > 0
        opacity: reveal.value
        width: closeAllRow.implicitWidth + 40
        height: 44
        radius: 22
        color: closeAllArea.pressed ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.18)
        scale: closeAllArea.pressed ? 0.94 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
        Row {
            id: closeAllRow
            anchors.centerIn: parent
            spacing: 8
            Icon { name: "close"; size: 18; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Close all")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: "white"
            }
        }
        MouseArea {
            id: closeAllArea
            anchors.fill: parent
            enabled: root.shown
            onClicked: {
                root.apps.stopAll()
                root.close()
            }
        }
    }
}
