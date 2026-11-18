// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Mines: clear the field without touching a mine. The numbers say how many
// mines are next to a square. Tap to open, press and hold (or switch to the
// flag) to mark a mine. The first tap is always safe. Best times are kept
// for each size.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/mines.json"
    readonly property var levels: [
        { name: qsTr("Easy"), cols: 8, rows: 10, mines: 10 },
        { name: qsTr("Medium"), cols: 9, rows: 12, mines: 20 },
        { name: qsTr("Hard"), cols: 10, rows: 14, mines: 36 }
    ]
    property int level: 0
    readonly property int cols: levels[level].cols
    readonly property int rows: levels[level].rows
    readonly property int total: levels[level].mines
    property var mine: []
    property var shown: []
    property var flag: []
    property var near: []
    property bool started: false
    property bool lost: false
    property bool won: false
    property bool flagMode: false
    property int seconds: 0
    property var bests: ({})
    property var blast: -1
    readonly property int flags: flag.filter(f => f).length

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        bests = s.bests || {}
        level = s.level || 0
        restart()
    }
    function save() { Files.writeText(storePath, JSON.stringify({ bests: bests, level: level })) }
    Component.onCompleted: load()

    function restart() {
        const n = cols * rows
        mine = new Array(n).fill(false); shown = new Array(n).fill(false); flag = new Array(n).fill(false); near = new Array(n).fill(0)
        started = false; lost = false; won = false; seconds = 0; blast = -1
    }
    function neighbours(i) {
        const out = [], r = Math.floor(i / cols), c = i % cols
        for (let dr = -1; dr <= 1; dr++)
            for (let dc = -1; dc <= 1; dc++) {
                if (!dr && !dc) continue
                const rr = r + dr, cc = c + dc
                if (rr >= 0 && rr < rows && cc >= 0 && cc < cols) out.push(rr * cols + cc)
            }
        return out
    }
    function plant(safe) {
        const m = mine.slice()
        const banned = new Set([safe].concat(neighbours(safe)))
        let placed = 0
        while (placed < total) {
            const i = Math.floor(Math.random() * cols * rows)
            if (m[i] || banned.has(i)) continue
            m[i] = true; placed++
        }
        mine = m
        near = m.map((_, i) => neighbours(i).filter(j => m[j]).length)
        started = true
    }
    function reveal(i) {
        if (lost || won || flag[i] || shown[i]) return
        if (!started) plant(i)
        const s = shown.slice()
        if (mine[i]) {
            blast = i; lost = true
            mine.forEach((m, k) => { if (m) s[k] = true })
            shown = s
            return
        }
        const stack = [i]
        while (stack.length) {
            const k = stack.pop()
            if (s[k] || flag[k]) continue
            s[k] = true
            if (near[k] === 0) neighbours(k).forEach(j => { if (!s[j]) stack.push(j) })
        }
        shown = s
        if (s.filter((v, k) => v && !mine[k]).length === cols * rows - total) win()
    }
    function toggleFlag(i) {
        if (lost || won || shown[i]) return
        const f = flag.slice(); f[i] = !f[i]; flag = f
    }
    function win() {
        won = true
        const k = String(level)
        if (!bests[k] || seconds < bests[k]) { const b = Object.assign({}, bests); b[k] = seconds; bests = b; save() }
    }
    function tap(i) {
        if (shown[i] && near[i] > 0) {         // chording: open what is around a satisfied number
            const around = neighbours(i)
            if (around.filter(j => flag[j]).length === near[i]) around.forEach(j => reveal(j))
        } else if (flagMode) {
            toggleFlag(i)
        } else {
            reveal(i)
        }
    }
    Timer { interval: 1000; repeat: true; running: app.started && !app.lost && !app.won; onTriggered: app.seconds++ }

    Column {
        anchors.fill: parent
        anchors.topMargin: Theme.statusBarHeight + 14
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        Text { text: qsTr("Mines"); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
        SegmentedControl {
            width: parent.width
            model: app.levels.map(l => l.name)
            currentIndex: app.level
            onActivated: (i) => { app.level = i; app.save(); app.restart() }
        }
        Row {
            width: parent.width
            Text { width: parent.width / 3; text: qsTr("Mines: %1").arg(app.total - app.flags); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
            Text {
                width: parent.width / 3; horizontalAlignment: Text.AlignHCenter
                text: app.won ? qsTr("You won!") : app.lost ? qsTr("Boom") : "●"
                font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.Bold
                color: app.won ? Theme.success : app.lost ? Theme.danger : Theme.textTertiary
            }
            Text { width: parent.width / 3; horizontalAlignment: Text.AlignRight; text: qsTr("%1 s").arg(app.seconds); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
        }
        Rectangle {
            id: board
            width: parent.width
            readonly property real cell: width / app.cols
            height: cell * app.rows
            radius: Theme.radius
            color: Theme.surface
            clip: true
            Repeater {
                model: app.cols * app.rows
                delegate: Item {
                    id: sq
                    required property int index
                    readonly property bool open: app.shown[index] === true
                    readonly property bool isMine: app.mine[index] === true
                    readonly property int n: app.near[index] || 0
                    x: (index % app.cols) * board.cell
                    y: Math.floor(index / app.cols) * board.cell
                    width: board.cell; height: board.cell
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1.5
                        radius: 6
                        color: sq.open ? (sq.isMine ? (app.blast === sq.index ? Theme.danger : Theme.surfaceRaised) : Theme.background) : Theme.surfaceRaised
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    Icon { anchors.centerIn: parent; visible: app.flag[sq.index] === true && !sq.open; name: "flag"; size: board.cell * 0.5; color: Theme.danger }
                    Icon { anchors.centerIn: parent; visible: sq.open && sq.isMine; name: "close"; size: board.cell * 0.5; color: Theme.text }
                    Text {
                        anchors.centerIn: parent
                        visible: sq.open && !sq.isMine && sq.n > 0
                        text: sq.n
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize + 2
                        font.weight: Font.Bold
                        color: sq.n === 1 ? Theme.highlight : sq.n === 2 ? Theme.success : sq.n === 3 ? Theme.danger : sq.n === 4 ? Theme.accentDeep : Theme.warning
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: app.tap(sq.index)
                        onPressAndHold: app.toggleFlag(sq.index)
                    }
                }
            }
        }
        Row {
            width: parent.width
            spacing: 12
            Button { width: (parent.width - 12) / 2; primary: app.flagMode; iconName: "flag"; text: app.flagMode ? qsTr("Flagging") : qsTr("Flag"); onClicked: app.flagMode = !app.flagMode }
            Button { width: (parent.width - 12) / 2; iconName: "refresh"; text: qsTr("New game"); onClicked: app.restart() }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: app.bests[String(app.level)] ? qsTr("Best time: %1 s").arg(app.bests[String(app.level)]) : qsTr("Press and hold a square to flag it.")
            font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary
        }
    }
}
