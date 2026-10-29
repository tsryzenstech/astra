// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The astraOS on-screen keyboard. It types into SysBoard's own fields and
// into apps (Wayland text-input) through the input method bridge.
//  - springs up from the bottom, rounded on top, swipe down to dismiss
//  - letters / numbers / symbols, shift (double tap: caps lock), automatic
//    capitals at the start of a sentence
//  - a bubble pops above the key under the finger; slide across keys and
//    the key under the finger types on release
//  - hold a vowel for accents, hold delete to repeat
//  - digits-only fields get a phone-style number pad
Item {
    id: root

    readonly property var bridge: Host.keyboard
    readonly property bool shown: !!bridge && bridge.visible
    readonly property real panelHeight: keys.height + 18 + Theme.homeIndicatorHeight
    readonly property real visibleHeight: Math.max(0, panelHeight * reveal.value)

    // Qt::InputMethodHints
    readonly property int hints: bridge ? bridge.hints : 0
    readonly property bool digitsOnly: (hints & (0x10000 /* ImhDigitsOnly */ | 0x20000 /* ImhFormattedNumbersOnly */ | 0x100000 /* ImhDialableCharactersOnly */)) !== 0
    readonly property bool dialable: (hints & 0x100000) !== 0
    readonly property bool noAutoUpper: (hints & (0x4 /* ImhNoAutoUppercase */ | 0x1 /* ImhHiddenText */)) !== 0

    property string page: "letters"     // letters, numbers, symbols
    property int shift: 0               // 0 off, 1 next letter, 2 caps lock
    property double lastShiftTap: 0

    width: parent ? parent.width : 393
    height: panelHeight
    visible: reveal.value > 0.005

    Spring { id: reveal; to: root.shown ? 1 : 0; response: 0.42; dampingFraction: 0.82 }
    onShownChanged: {
        reveal.animateTo(shown ? 1 : 0, 0)
        if (shown) {
            page = "letters"
            autoShift()
        }
    }
    function autoShift() {
        if (shift < 2)
            shift = !noAutoUpper && bridge && bridge.shiftAtStart ? 1 : 0
    }
    Connections {
        target: root.bridge
        ignoreUnknownSignals: true
        function onStateChanged() { root.autoShift() }
    }

    // ---- layouts ---------------------------------------------------------------
    readonly property var letterRows: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"],
        ["123", ",", " ", ".", "⏎"]
    ]
    readonly property var numberRows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
        ["#+=", ".", ",", "?", "!", "'", "⌫"],
        ["ABC", ",", " ", ".", "⏎"]
    ]
    readonly property var symbolRows: [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"],
        ["123", ".", ",", "?", "!", "'", "⌫"],
        ["ABC", ",", " ", ".", "⏎"]
    ]
    readonly property var padRows: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [dialable ? "+*#" : ".", "0", "⌫"]]
    readonly property var rows: digitsOnly ? padRows : page === "numbers" ? numberRows : page === "symbols" ? symbolRows : letterRows
    readonly property var accents: ({
        a: "àáâäãå", e: "èéêëē", i: "ìíîï", o: "òóôöõø", u: "ùúûü", c: "çć", n: "ñń", s: "ßś", y: "ÿ", z: "žź"
    })

    function isSpecial(k) { return ["⇧", "⌫", "123", "ABC", "#+=", "⏎", " ", "+*#"].indexOf(k) >= 0 }
    function label(k) {
        if (k === " ")
            return Language.current === "it" ? "spazio" : "space"
        if (k === "⏎") {
            switch (bridge ? bridge.enterKeyType : 0) {
            case 2: return qsTr("Done")
            case 3: return qsTr("Go")
            case 4: return qsTr("Send")
            case 5: return qsTr("Search")
            case 6: return qsTr("Next")
            case 7: return qsTr("Previous")
            }
            return qsTr("return")
        }
        if (!isSpecial(k) && page === "letters" && shift > 0)
            return k.toUpperCase()
        return k
    }
    function type(k) {
        if (!bridge)
            return
        switch (k) {
        case "⌫": bridge.backspace(); return
        case "⏎": bridge.enter(); return
        case "123": page = "numbers"; return
        case "#+=": page = "symbols"; return
        case "ABC": page = "letters"; return
        case "+*#": bridge.commit("+"); return
        case "⇧": {
            const now = Date.now()
            shift = shift === 2 ? 0 : (now - lastShiftTap < 350 ? 2 : (shift === 1 ? 0 : 1))
            lastShiftTap = now
            return
        }
        }
        bridge.commit(page === "letters" && shift > 0 ? k.toUpperCase() : k)
        if (shift === 1)
            shift = 0
        // Space or apostrophe go back to letters, like iOS.
        if (page !== "letters" && (k === " " || k === "'"))
            page = "letters"
    }

    // ---- panel ---------------------------------------------------------------
    Item {
        id: panel
        width: parent.width
        height: root.panelHeight
        y: (1 - reveal.value) * (root.panelHeight + 20) + Math.max(0, dismiss.offset)

        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: -40
            radius: 28
            color: "#1E1E22"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.06)
        }
        // Grab handle: swipe down to dismiss.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            width: 36
            height: 4
            radius: 2
            color: Qt.rgba(1, 1, 1, 0.25)
        }
        MouseArea {
            id: dismiss
            width: parent.width
            height: 18
            property real startY
            property real offset: 0
            onPressed: (m) => startY = m.y
            onPositionChanged: (m) => offset = m.y - startY
            onReleased: {
                if (offset > 40 && root.bridge)
                    root.bridge.hide()
                offset = 0
            }
        }

        Column {
            id: keys
            x: 4
            y: 16
            width: parent.width - 8
            spacing: 10

            Repeater {
                model: root.rows
                delegate: Row {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property real unit: (keys.width - 6 * 9) / (root.digitsOnly ? 3 : 10)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: root.digitsOnly ? 6 : 6

                    Repeater {
                        model: row.modelData
                        delegate: Item {
                            id: key
                            required property string modelData
                            readonly property bool special: root.isSpecial(modelData)
                            readonly property bool pressed: touch.current === key
                            width: {
                                if (root.digitsOnly)
                                    return (keys.width - 12) / 3
                                if (modelData === " ")
                                    return row.unit * 5 + 24
                                if (modelData === "⏎")
                                    return row.unit * 2 + 6
                                if (modelData === "⇧" || modelData === "⌫" || modelData === "#+=" || (modelData === "123" && row.index === 2))
                                    return row.unit * 1.35
                                if (["123", "ABC"].indexOf(modelData) >= 0)
                                    return row.unit * 1.2
                                if (root.page !== "letters" && row.index === 2)
                                    return row.unit * 1.25
                                return row.unit
                            }
                            height: root.digitsOnly ? 52 : 46

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                readonly property bool lit: key.modelData === "⇧" && root.shift > 0
                                color: key.pressed ? (key.special ? "#5A5A62" : "#6E6E76")
                                     : lit ? "white"
                                     : key.modelData === "⏎" && root.bridge && root.bridge.enterKeyType > 1 ? Theme.accent
                                     : key.special ? "#3A3A40" : "#56565D"
                                scale: key.pressed && key.special ? 0.94 : 1
                                Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                                Behavior on color { ColorAnimation { duration: 90 } }
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: key.modelData !== "⇧" && key.modelData !== "⌫"
                                text: root.label(key.modelData)
                                font.family: Theme.fontFamily
                                font.pixelSize: key.special ? 15 : (root.digitsOnly ? 26 : 22)
                                font.weight: key.special ? Font.Medium : Font.Normal
                                color: "white"
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: key.modelData === "⇧" || key.modelData === "⌫"
                                name: key.modelData === "⌫" ? "backspace" : "arrow-up"
                                size: 22
                                color: key.modelData === "⇧" && root.shift > 0 ? "#1E1E22" : "white"
                            }
                            Rectangle {
                                // Caps lock underline
                                visible: key.modelData === "⇧" && root.shift === 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 7
                                width: 14
                                height: 2
                                radius: 1
                                color: "#1E1E22"
                            }
                        }
                    }
                }
            }
        }

        // ---- touch: one area for the whole keyboard --------------------------
        MouseArea {
            id: touch
            anchors.fill: keys
            anchors.margins: -5
            preventStealing: true
            property Item current: null
            property string accentBase: ""
            property int accentIndex: -1

            function keyAt(x, y) {
                const p = mapToItem(keys, x, y)
                let best = null, bestDist = 1e9
                for (let r = 0; r < keys.children.length; r++) {
                    const row = keys.children[r]
                    if (!row.children)
                        continue
                    for (let i = 0; i < row.children.length; i++) {
                        const k = row.children[i]
                        if (k.modelData === undefined)
                            continue
                        const kp = k.mapToItem(keys, k.width / 2, k.height / 2)
                        const dx = Math.max(0, Math.abs(p.x - kp.x) - k.width / 2)
                        const dy = Math.max(0, Math.abs(p.y - kp.y) - k.height / 2)
                        const d = dx * dx + dy * dy * 1.5
                        if (d < bestDist) {
                            bestDist = d
                            best = k
                        }
                    }
                }
                return bestDist < 900 ? best : null
            }
            onPressed: (m) => {
                current = keyAt(m.x, m.y)
                accentBase = ""
                if (current)
                    hold.restart()
            }
            onPositionChanged: (m) => {
                if (accentBase !== "") {
                    const p = mapToItem(accentPopup, m.x, m.y)
                    accentIndex = Math.max(0, Math.min(root.accents[accentBase].length - 1, Math.floor(p.x / 44)))
                    return
                }
                const k = keyAt(m.x, m.y)
                if (k !== current) {
                    current = k
                    hold.restart()
                    repeat.stop()
                }
            }
            onReleased: {
                hold.stop()
                repeat.stop()
                if (accentBase !== "") {
                    const ch = root.accents[accentBase][Math.max(0, accentIndex)]
                    root.bridge.commit(root.shift > 0 ? ch.toUpperCase() : ch)
                    if (root.shift === 1)
                        root.shift = 0
                } else if (current && !(current.modelData === "⌫" && repeat.fired)) {
                    root.type(current.modelData)
                }
                accentBase = ""
                current = null
                repeat.fired = false
            }
            onCanceled: {
                hold.stop()
                repeat.stop()
                accentBase = ""
                current = null
            }
            Timer {
                id: hold
                interval: 420
                onTriggered: {
                    const k = touch.current ? touch.current.modelData : ""
                    if (k === "⌫") {
                        root.type("⌫")
                        repeat.fired = true
                        repeat.start()
                    } else if (root.page === "letters" && root.accents[k]) {
                        touch.accentBase = k
                        touch.accentIndex = 0
                    }
                }
            }
            Timer {
                id: repeat
                property bool fired: false
                interval: 80
                repeat: true
                onTriggered: root.type("⌫")
            }
        }

        // Key preview bubble
        Rectangle {
            id: bubble
            readonly property Item k: touch.current && !touch.current.special && touch.accentBase === "" && !root.digitsOnly ? touch.current : null
            visible: k !== null
            width: k ? k.width + 18 : 0
            height: 62
            radius: 14
            color: "#6E6E76"
            x: k ? k.mapToItem(panel, 0, 0).x - 9 : 0
            y: k ? k.mapToItem(panel, 0, 0).y - height - 6 : 0
            scale: visible ? 1 : 0.6
            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
            Text {
                anchors.centerIn: parent
                text: bubble.k ? root.label(bubble.k.modelData) : ""
                font.family: Theme.fontFamily
                font.pixelSize: 32
                color: "white"
            }
        }

        // Accents
        Rectangle {
            id: accentPopup
            visible: touch.accentBase !== ""
            readonly property string list: touch.accentBase ? root.accents[touch.accentBase] : ""
            width: list.length * 44 + 8
            height: 56
            radius: 14
            color: "#6E6E76"
            x: touch.current ? Math.max(4, Math.min(panel.width - width - 4, touch.current.mapToItem(panel, 0, 0).x - 4)) : 0
            y: touch.current ? touch.current.mapToItem(panel, 0, 0).y - height - 8 : 0
            Row {
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: accentPopup.list.split("")
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: 44
                        height: 46
                        radius: 10
                        color: index === touch.accentIndex ? Theme.accent : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: root.shift > 0 ? modelData.toUpperCase() : modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 24
                            color: "white"
                        }
                    }
                }
            }
        }
    }
}
