// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Focus Timer: work in rounds with short breaks (the Pomodoro way). The timer
// follows the clock, so it stays right while the screen is off, and a
// notification tells when a round ends.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/focus.json"
    // Phases: 0 focus, 1 short break, 2 long break
    property int phase: 0
    property bool running: false
    property real endsAt: 0              // ms since epoch, while running
    property real remaining: 25 * 60000    // ms, while paused
    property int round: 1                // 1..rounds
    property int focusMinutes: 25
    property int breakMinutes: 5
    property int longMinutes: 15
    property int rounds: 4
    property var log: ({})               // { "2026-11-18": completed focus rounds }
    property real now: Date.now()
    readonly property real timeLeft: running ? Math.max(0, endsAt - now) : remaining
    readonly property real phaseLength: [focusMinutes, breakMinutes, longMinutes][phase] * 60000

    function key() { const d = new Date(); return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() }
    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        focusMinutes = s.focus || 25; breakMinutes = s.brk || 5; longMinutes = s.long || 15; rounds = s.rounds || 4
        log = s.log || {}
        remaining = phaseLength
    }
    function save() { Files.writeText(storePath, JSON.stringify({ focus: focusMinutes, brk: breakMinutes, long: longMinutes, rounds: rounds, log: log })) }
    Component.onCompleted: load()

    function start() { endsAt = Date.now() + remaining; running = true; now = Date.now() }
    function pause() { remaining = Math.max(0, endsAt - Date.now()); running = false }
    function reset() { running = false; remaining = phaseLength }
    function setPhase(p) { phase = p; running = false; remaining = phaseLength }
    function finished() {
        running = false
        const wasFocus = phase === 0
        if (wasFocus) {
            const l = Object.assign({}, log)
            l[key()] = (l[key()] || 0) + 1
            log = l
            save()
        }
        const next = wasFocus ? (round >= rounds ? 2 : 1) : 0
        if (!wasFocus) round = phase === 2 ? 1 : round + 1
        Notifications.post(wasFocus ? qsTr("Time for a break") : qsTr("Back to focus"),
                           wasFocus ? qsTr("Round %1 of %2 is done.").arg(round).arg(rounds) : qsTr("Round %1 of %2 starts.").arg(round).arg(rounds))
        setPhase(next)
        start()
    }
    Timer {
        interval: 250; repeat: true; running: app.running
        onTriggered: { app.now = Date.now(); if (app.now >= app.endsAt) app.finished() }
    }
    function clock(ms) {
        const s = Math.ceil(ms / 1000)
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    readonly property int doneToday: log[key()] || 0

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(mainPage) }

    Component {
        id: mainPage
        Page {
            title: qsTr("Focus")
            actions: IconButton { iconName: "sliders"; size: 38; onClicked: stack.open(settingsPage) }
            centeredTitle: false

            SegmentedControl {
                width: parent.width
                model: [qsTr("Focus"), qsTr("Break"), qsTr("Long break")]
                currentIndex: app.phase
                onActivated: (i) => app.setPhase(i)
            }
            Item {
                width: parent.width
                height: width * 0.8
                Rectangle {
                    id: ring
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height); height: width; radius: width / 2
                    color: "transparent"
                    border.width: 12
                    border.color: Theme.surfaceRaised
                }
                Canvas {
                    id: arc
                    anchors.fill: ring
                    property real progress: app.phaseLength > 0 ? 1 - app.timeLeft / app.phaseLength : 0
                    property color tint: Theme.accent
                    onProgressChanged: requestPaint()
                    onTintChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d")
                        c.reset()
                        c.lineWidth = 12
                        c.lineCap = "round"
                        c.strokeStyle = tint
                        c.beginPath()
                        c.arc(width / 2, height / 2, width / 2 - 6, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.002, progress))
                        c.stroke()
                    }
                }
                Column {
                    anchors.centerIn: ring
                    spacing: 2
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.clock(app.timeLeft); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize + 14; font.weight: Font.Light; color: Theme.text }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: app.phase === 0 ? qsTr("Round %1 of %2").arg(app.round).arg(app.rounds) : app.phase === 1 ? qsTr("Short break") : qsTr("Long break")
                        font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary
                    }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Button { width: 130; primary: false; text: qsTr("Reset"); onClicked: app.reset() }
                Button { width: 170; text: app.running ? qsTr("Pause") : qsTr("Start"); iconName: app.running ? "pause" : "play"; onClicked: app.running ? app.pause() : app.start() }
            }
            Card {
                Row {
                    width: parent.width
                    Column {
                        width: parent.width / 2
                        Text { text: app.doneToday; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text { text: qsTr("rounds today"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
                    }
                    Column {
                        width: parent.width / 2
                        Text { text: qsTr("%1 min").arg(app.doneToday * app.focusMinutes); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text { text: qsTr("focused today"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
                    }
                }
            }
        }
    }

    Component {
        id: settingsPage
        Page {
            title: qsTr("Timer")
            ListGroup {
                title: qsTr("Minutes")
                Repeater {
                    model: [
                        { id: "focus", label: qsTr("Focus"), min: 5, max: 90 },
                        { id: "brk", label: qsTr("Short break"), min: 1, max: 30 },
                        { id: "long", label: qsTr("Long break"), min: 5, max: 60 },
                        { id: "rounds", label: qsTr("Rounds before a long break"), min: 2, max: 8 }
                    ]
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        readonly property int val: modelData.id === "focus" ? app.focusMinutes : modelData.id === "brk" ? app.breakMinutes : modelData.id === "long" ? app.longMinutes : app.rounds
                        text: modelData.label
                        separator: index < 3
                        Row {
                            spacing: 8
                            anchors.verticalCenter: parent.verticalCenter
                            IconButton { iconName: "minus"; size: 32; onClicked: app.setValue(modelData.id, Math.max(modelData.min, val - 1)) }
                            Text { width: 34; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: val; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
                            IconButton { iconName: "plus"; size: 32; onClicked: app.setValue(modelData.id, Math.min(modelData.max, val + 1)) }
                        }
                    }
                }
            }
        }
    }
    function setValue(id, v) {
        if (id === "focus") focusMinutes = v
        else if (id === "brk") breakMinutes = v
        else if (id === "long") longMinutes = v
        else rounds = v
        if (!running) remaining = phaseLength
        save()
    }
}
