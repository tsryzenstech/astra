// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The emoji page of the keyboard: every emoji of the Twemoji set (Unicode
// 14) on pages that scroll sideways, a category bar to jump between them,
// recents first, and skin tones on a long press (the last choice sticks).
Item {
    id: root

    property var keyboard            // the Keyboard (colours, bridge, page)
    signal typed(string text)

    readonly property var recent: Settings.values["keyboard.recent_emoji"] || []
    readonly property var preferred: Settings.values["keyboard.emoji_tones"] || ({})
    readonly property var sections: [{ id: "recent", icon: "", emoji: recent }].concat(EmojiData.groups)
    readonly property int rows: 4
    readonly property real cell: Math.floor(height - bar.height - title.height) / rows

    function titleOf(id) {
        switch (id) {
        case "recent": return qsTr("Frequently Used")
        case "smileys": return qsTr("Smileys & Emotion")
        case "people": return qsTr("People & Body")
        case "nature": return qsTr("Animals & Nature")
        case "food": return qsTr("Food & Drink")
        case "travel": return qsTr("Travel & Places")
        case "activities": return qsTr("Activities")
        case "objects": return qsTr("Objects")
        case "symbols": return qsTr("Symbols")
        case "flags": return qsTr("Flags")
        }
        return ""
    }
    function shown(e) { return preferred[e] || e }
    function pick(e) {
        const list = [e].concat(recent.filter(r => r !== e)).slice(0, 4 * 8)
        Settings.setValue("keyboard.recent_emoji", list)
        typed(e)
    }
    function setTone(base, variant) {
        const p = Object.assign({}, preferred)
        p[base] = variant
        Settings.setValue("keyboard.emoji_tones", p)
        pick(variant)
    }

    // Start at the first page each time the emoji page opens.
    onVisibleChanged: if (visible) list.positionViewAtBeginning()

    Text {
        id: title
        x: 10
        height: 22
        text: root.titleOf(root.sections[Math.max(0, list.current)].id)
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        color: Qt.alpha(root.keyboard.labelColor, 0.55)
    }

    ListView {
        id: list
        anchors.top: title.bottom
        width: parent.width
        height: root.cell * root.rows
        orientation: ListView.Horizontal
        boundsBehavior: Flickable.DragOverBounds
        cacheBuffer: Math.max(0, width * 2)
        clip: true
        model: root.sections
        readonly property int current: Math.max(0, indexAt(contentX + 1, height / 2))
        delegate: Item {
            id: section
            required property var modelData
            required property int index
            readonly property int columns: Math.max(1, Math.ceil(modelData.emoji.length / root.rows))
            width: modelData.emoji.length ? columns * root.cell + 8 : (index === 0 ? list.width * 0.6 : 0)
            height: list.height

            Text {
                visible: section.index === 0 && section.modelData.emoji.length === 0
                anchors.centerIn: parent
                width: parent.width - 20
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("Emoji you use show up here.")
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: Qt.alpha(root.keyboard.labelColor, 0.5)
            }
            Grid {
                x: 4
                flow: Grid.TopToBottom
                rows: root.rows
                Repeater {
                    model: section.modelData.emoji
                    delegate: Item {
                        id: cellItem
                        required property string modelData
                        readonly property string face: section.index === 0 ? modelData : root.shown(modelData)
                        width: root.cell
                        height: root.cell
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: 10
                            color: tap.pressed ? Qt.alpha(root.keyboard.labelColor, 0.12) : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cellItem.face
                            font.pixelSize: root.cell * 0.68
                            scale: tap.pressed ? 1.18 : 1
                            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
                        }
                        MouseArea {
                            id: tap
                            anchors.fill: parent
                            pressAndHoldInterval: 350
                            onClicked: root.pick(cellItem.face)
                            onPressAndHold: {
                                const base = cellItem.modelData.replace(/[\u{1F3FB}-\u{1F3FF}]/gu, "")
                                if (EmojiData.tones[base])
                                    tones.openFor(cellItem, base)
                            }
                        }
                    }
                }
            }
        }
    }

    // Category bar
    Row {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 38
        spacing: 0

        Item {
            width: 52
            height: parent.height
            Rectangle {
                anchors.centerIn: parent
                width: 44
                height: 32
                radius: 8
                color: root.keyboard.specialColor
                Text {
                    anchors.centerIn: parent
                    text: "ABC"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: root.keyboard.labelColor
                }
            }
            MouseArea { anchors.fill: parent; onClicked: root.keyboard.page = "letters" }
        }
        Repeater {
            model: root.sections
            delegate: Item {
                required property var modelData
                required property int index
                width: (bar.width - 52 - 52) / root.sections.length
                height: bar.height
                Rectangle {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    radius: 15
                    color: list.current === parent.index ? Qt.alpha(root.keyboard.labelColor, 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                Text {
                    visible: parent.modelData.icon !== ""
                    anchors.centerIn: parent
                    text: parent.modelData.icon
                    font.pixelSize: 17
                    opacity: list.current === parent.index ? 1 : 0.55
                }
                Icon {
                    visible: parent.modelData.icon === ""
                    anchors.centerIn: parent
                    name: "clock"
                    size: 18
                    color: root.keyboard.labelColor
                    opacity: list.current === parent.index ? 1 : 0.55
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: list.positionViewAtIndex(parent.index, ListView.Beginning)
                }
            }
        }
        Item {
            width: 52
            height: parent.height
            Rectangle {
                anchors.centerIn: parent
                width: 44
                height: 32
                radius: 8
                color: del.pressed ? root.keyboard.pressedColor : root.keyboard.specialColor
                Icon { anchors.centerIn: parent; name: "backspace"; size: 20; color: root.keyboard.labelColor }
            }
            MouseArea {
                id: del
                anchors.fill: parent
                onClicked: root.keyboard.bridge.backspace()
                onPressAndHold: delRepeat.start()
                onReleased: delRepeat.stop()
                onCanceled: delRepeat.stop()
                Timer { id: delRepeat; interval: 80; repeat: true; onTriggered: root.keyboard.bridge.backspace() }
            }
        }
    }

    // Skin tones
    MouseArea {
        anchors.fill: parent
        visible: tones.visible
        onClicked: tones.visible = false
    }
    Rectangle {
        id: tones
        property string base: ""
        visible: false
        readonly property var options: base ? [base].concat(EmojiData.tones[base] || []) : []
        function openFor(item, b) {
            base = b
            const p = item.mapToItem(root, 0, 0)
            x = Math.max(4, Math.min(root.width - width - 4, p.x + item.width / 2 - width / 2))
            y = Math.max(-height + 20, p.y - height - 4)
            visible = true
            pop.value = 0.6
            pop.animateTo(1, 0)
        }
        Spring { id: pop; to: 1; response: 0.3; dampingFraction: 0.62 }
        scale: pop.value
        width: options.length * 44 + 8
        height: 52
        radius: 14
        color: root.keyboard.keyColor
        border.width: Theme.light ? 1 : 0
        border.color: Qt.rgba(0, 0, 0, 0.12)
        Row {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: tones.options
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: 44
                    height: 44
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: (root.preferred[tones.base] || tones.base) === parent.modelData ? Qt.alpha(Theme.accent, 0.25) : "transparent"
                    }
                    Text { anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 28 }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            tones.visible = false
                            root.setTone(tones.base, parent.modelData)
                        }
                    }
                }
            }
        }
    }
}
