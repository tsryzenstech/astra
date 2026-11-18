// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// 2048: swipe to slide the tiles; equal tiles that meet join. Reach 2048, or
// go on for a higher score. The best score is kept.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/game2048.json"
    property var cells: []              // 16 numbers, 0: empty
    property var fresh: ({})            // index -> true for the tile that just appeared
    property int score: 0
    property int best: 0
    property bool won: false
    property bool keepGoing: false
    property bool over: false
    property var undoCells: []
    property int undoScore: 0

    function save() { Files.writeText(storePath, JSON.stringify({ cells: cells, score: score, best: best, won: won, keepGoing: keepGoing })) }
    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        best = s.best || 0
        if (s.cells && s.cells.length === 16) {
            cells = s.cells; score = s.score || 0; won = !!s.won; keepGoing = !!s.keepGoing
            over = !canMove(cells)
        } else {
            restart()
        }
    }
    Component.onCompleted: load()

    function spawn(list) {
        const empty = []
        list.forEach((v, i) => { if (!v) empty.push(i) })
        if (!empty.length) return -1
        const i = empty[Math.floor(Math.random() * empty.length)]
        list[i] = Math.random() < 0.9 ? 2 : 4
        return i
    }
    function restart() {
        const list = new Array(16).fill(0)
        const a = spawn(list), b = spawn(list)
        cells = list; fresh = ({}); fresh[a] = true; fresh[b] = true
        score = 0; won = false; keepGoing = false; over = false; undoCells = []
        save()
    }
    function canMove(list) {
        for (let r = 0; r < 4; r++)
            for (let c = 0; c < 4; c++) {
                const v = list[r * 4 + c]
                if (!v) return true
                if (c < 3 && list[r * 4 + c + 1] === v) return true
                if (r < 3 && list[(r + 1) * 4 + c] === v) return true
            }
        return false
    }
    // dir: 0 left, 1 right, 2 up, 3 down
    function slide(dir) {
        const out = cells.slice()
        let gained = 0
        let moved = false
        for (let line = 0; line < 4; line++) {
            const idx = []
            for (let k = 0; k < 4; k++) {
                const kk = (dir === 1 || dir === 3) ? 3 - k : k
                idx.push(dir < 2 ? line * 4 + kk : kk * 4 + line)
            }
            const vals = idx.map(i => out[i]).filter(v => v)
            const merged = []
            for (let k = 0; k < vals.length; k++) {
                if (k + 1 < vals.length && vals[k] === vals[k + 1]) { merged.push(vals[k] * 2); gained += vals[k] * 2; k++ }
                else merged.push(vals[k])
            }
            while (merged.length < 4) merged.push(0)
            idx.forEach((i, k) => { if (out[i] !== merged[k]) moved = true; out[i] = merged[k] })
        }
        if (!moved) return
        undoCells = cells.slice(); undoScore = score
        const at = spawn(out)
        fresh = ({}); fresh[at] = true
        cells = out
        score += gained
        best = Math.max(best, score)
        if (!won && out.indexOf(2048) >= 0) won = true
        over = !canMove(out)
        save()
    }
    function undo() {
        if (!undoCells.length) return
        cells = undoCells; score = undoScore; undoCells = []; over = false; fresh = ({})
        save()
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Theme.statusBarHeight + 14
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 16

        Row {
            width: parent.width
            Text { width: parent.width - 220; anchors.verticalCenter: parent.verticalCenter; text: "2048"; font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
            Repeater {
                model: [{ label: qsTr("Score"), value: app.score }, { label: qsTr("Best"), value: app.best }]
                delegate: Rectangle {
                    required property var modelData
                    width: 104; height: 56; radius: Theme.radius
                    color: Theme.surface
                    Column {
                        anchors.centerIn: parent
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label.toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.value; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                    }
                }
            }
        }
        Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Join the tiles and get to 2048."); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; color: Theme.textSecondary }

        Rectangle {
            id: board
            width: parent.width
            height: width
            radius: Theme.cardRadius
            color: Theme.surface
            readonly property real gap: 10
            readonly property real tile: (width - gap * 5) / 4

            Repeater {
                model: 16
                delegate: Rectangle {
                    required property int index
                    x: board.gap + (index % 4) * (board.tile + board.gap)
                    y: board.gap + Math.floor(index / 4) * (board.tile + board.gap)
                    width: board.tile; height: board.tile; radius: Theme.radiusSmall
                    color: Theme.surfaceRaised
                }
            }
            Repeater {
                model: 16
                delegate: Item {
                    id: t
                    required property int index
                    readonly property int v: app.cells[index] || 0
                    readonly property real level: v ? Math.log(v) / Math.LN2 : 0
                    x: board.gap + (index % 4) * (board.tile + board.gap)
                    y: board.gap + Math.floor(index / 4) * (board.tile + board.gap)
                    width: board.tile; height: board.tile
                    visible: v > 0
                    scale: 1
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSmall
                        color: t.level >= 8 ? Theme.accentDeep : Theme.accent
                        opacity: Math.min(1, 0.16 + t.level * 0.085)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: t.v
                        font.family: Theme.fontFamily
                        font.pixelSize: t.v < 100 ? Theme.titleSize + 6 : t.v < 1000 ? Theme.titleSize : Theme.headlineSize
                        font.weight: Font.Bold
                        color: t.level >= 3 ? Theme.accentText : Theme.text
                    }
                    SequentialAnimation on scale {
                        running: app.fresh[t.index] === true && t.v > 0
                        NumberAnimation { from: 0.4; to: 1; duration: 160; easing.type: Easing.OutBack }
                    }
                }
            }

            // Swipes anywhere on the board, and arrow keys on a keyboard.
            MouseArea {
                anchors.fill: parent
                property real sx; property real sy
                onPressed: (m) => { sx = m.x; sy = m.y }
                onReleased: (m) => {
                    const dx = m.x - sx, dy = m.y - sy
                    if (Math.max(Math.abs(dx), Math.abs(dy)) < 24) return
                    app.slide(Math.abs(dx) > Math.abs(dy) ? (dx < 0 ? 0 : 1) : (dy < 0 ? 2 : 3))
                }
            }
            focus: true
            Keys.onLeftPressed: app.slide(0)
            Keys.onRightPressed: app.slide(1)
            Keys.onUpPressed: app.slide(2)
            Keys.onDownPressed: app.slide(3)

            Rectangle {
                visible: (app.won && !app.keepGoing) || app.over
                anchors.fill: parent
                radius: Theme.cardRadius
                color: Theme.glassStrong
                Column {
                    anchors.centerIn: parent
                    spacing: 14
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.over ? qsTr("Game over") : qsTr("You made 2048!"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.accentText }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 10
                        Button { visible: !app.over; text: qsTr("Keep going"); primary: false; onClicked: { app.keepGoing = true; app.save() } }
                        Button { text: qsTr("New game"); onClicked: app.restart() }
                    }
                }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Button { width: 150; primary: false; iconName: "undo"; text: qsTr("Undo"); enabled: app.undoCells.length > 0; onClicked: app.undo() }
            Button { width: 150; iconName: "refresh"; text: qsTr("New game"); onClicked: app.restart() }
        }
    }
}
