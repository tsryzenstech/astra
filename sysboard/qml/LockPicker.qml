// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// The lock screens to choose from (hold the lock screen for three seconds): a row of cards you swipe
// through, the one in the middle bigger; Customise opens it for editing, + makes a new one from a
// picture of the Gallery. It lives over the lock screen: the phone stays locked.
Item {
    id: root

    property var shell
    property Item blurSource: null
    property bool opened: false
    // What to open in the editor: the slot, or 0.
    property int editingId: 0
    property bool choosing: false            // the wallpaper picker, for a new lock screen

    anchors.fill: parent
    visible: reveal.value > 0.01
    z: 60

    function open() {
        LockSlots.select(LockSlots.currentId)
        editingId = 0
        choosing = false
        opened = true
        const i = LockSlots.slots.findIndex(s => s.id === LockSlots.currentId)
        list.currentIndex = Math.max(0, i)
        list.positionViewAtIndex(list.currentIndex, ListView.Center)
    }
    function close() { opened = false }

    Spring { id: reveal; to: root.opened ? 1 : 0; response: 0.45; dampingFraction: 0.86 }

    // The screen behind, blurred and dimmed.
    BlurLayer {
        anchors.fill: parent
        source: root.blurSource
        amount: reveal.value
        dim: 0.45
    }
    MouseArea { anchors.fill: parent; enabled: root.opened }

    readonly property real cardW: width * 0.62
    readonly property real cardH: cardW * height / width
    opacity: reveal.value

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.statusBarHeight + 18
        text: (LockSlots.slots[list.currentIndex] ? LockSlots.slots[list.currentIndex].name : "").toUpperCase()
        font.family: Theme.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        font.letterSpacing: 1.2
        color: "white"
    }

    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        y: Theme.statusBarHeight + 58
        height: root.cardH + 20
        orientation: ListView.Horizontal
        model: LockSlots.slots
        spacing: 18
        leftMargin: (root.width - root.cardW) / 2
        rightMargin: leftMargin
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: (root.width - root.cardW) / 2
        preferredHighlightEnd: (root.width + root.cardW) / 2
        highlightMoveDuration: 260
        boundsBehavior: Flickable.StopAtBounds
        clip: false
        onCurrentIndexChanged: {
            const s = LockSlots.slots[currentIndex]
            if (s && root.opened && s.id !== LockSlots.currentId)
                LockSlots.select(s.id)
        }

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool current: ListView.isCurrentItem
            width: root.cardW
            height: root.cardH
            scale: current ? 1 : 0.86
            Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
            opacity: current ? 1 : 0.8

            Item {
                id: face
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: cardMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Item {
                    width: root.width
                    height: root.height
                    scale: card.width / root.width
                    transformOrigin: Item.TopLeft
                    LockFace { anchors.fill: parent; slot: card.modelData; showLock: false }
                }
            }
            Rectangle { id: cardMask; anchors.fill: parent; radius: 30; visible: false; layer.enabled: true }
            Rectangle {
                anchors.fill: parent
                radius: 30
                color: "transparent"
                border.width: card.current ? 2 : 0
                border.color: Qt.rgba(1, 1, 1, 0.55)
            }
            MouseArea { anchors.fill: parent; onClicked: list.currentIndex = card.index }
        }
    }

    Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        y: list.y + list.height + 6
        spacing: 12
        Repeater {
            model: LockSlots.slots.length
            Rectangle {
                required property int index
                width: 7
                height: 7
                radius: 3.5
                color: "white"
                opacity: index === list.currentIndex ? 1 : 0.35
            }
        }
    }

    // Customise, and a new lock screen.
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.homeIndicatorHeight + 26
        spacing: 14
        Glass {
            id: customise
            width: root.width - 40 - 14 - 56
            height: 56
            source: root.blurSource
            tint: Qt.rgba(1, 1, 1, 0.16)
            onClicked: root.editingId = LockSlots.slots[list.currentIndex].id
            Text {
                anchors.centerIn: parent
                text: qsTr("Customise")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.DemiBold
                color: "white"
            }
        }
        Rectangle {
            width: 56
            height: 56
            radius: 28
            color: Theme.accent
            Icon { anchors.centerIn: parent; name: "plus"; size: 26; color: "white" }
            scale: plusArea.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            MouseArea { id: plusArea; anchors.fill: parent; onClicked: root.choosing = true }
        }
    }

    // Done: back to the lock screen.
    MouseArea {
        x: 0
        y: 0
        width: 90
        height: Theme.statusBarHeight + 56
        onClicked: root.close()
    }
    Glass {
        x: 12
        y: Theme.statusBarHeight + 6
        width: 76
        height: 36
        source: root.blurSource
        onClicked: root.close()
        Text {
            anchors.centerIn: parent
            text: qsTr("Done")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            font.weight: Font.DemiBold
            color: "white"
        }
    }

    // The editor, over the cards.
    LockEditor {
        id: editor
        anchors.fill: parent
        blurSource: root.blurSource
        slotId: root.editingId
        shown: root.editingId !== 0
        onFinished: root.editingId = 0
        onDeleted: { LockSlots.remove(root.editingId); root.editingId = 0; list.currentIndex = 0 }
    }

    // A picture for a new lock screen.
    WallpaperChooser {
        anchors.fill: parent
        shown: root.choosing
        blurSource: root.blurSource
        onChosen: (path) => {
            root.choosing = false
            const id = LockSlots.add(path)
            const i = LockSlots.slots.findIndex(s => s.id === id)
            Qt.callLater(function() {
                list.currentIndex = Math.max(0, i)
                root.editingId = id
            })
        }
        onCancelled: root.choosing = false
    }
}
