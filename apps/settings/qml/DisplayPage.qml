// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Display: brightness, night light, refresh rate, resolution,
// display and text size, screen timeout. Resolution, refresh rate and
// display size apply when the system UI restarts.
Page {
    id: page
    title: qsTr("Display")

    readonly property var info: Display.state
    readonly property var modes: info.modes || []
    // Saved mode, or the current one.
    readonly property string modeKey: Settings.values["display.mode"]
                                      || (info.width ? info.width + "x" + info.height + "@" + info.refresh : "")
    readonly property var resolutions: {
        const seen = {}, out = []
        for (const m of modes) {
            const k = m.width + "x" + m.height
            if (!seen[k]) {
                seen[k] = true
                out.push({ width: m.width, height: m.height })
            }
        }
        return out.sort((a, b) => b.width - a.width)
    }
    readonly property var current: {
        const m = /^(\d+)x(\d+)@(\d+)/.exec(modeKey)
        return m ? { width: +m[1], height: +m[2], refresh: +m[3] } : { width: 0, height: 0, refresh: 0 }
    }
    readonly property var refreshRates: modes.filter(m => m.width === current.width && m.height === current.height)
                                             .map(m => m.refresh).sort((a, b) => a - b)
    property bool needsRestart: false

    function setMode(width, height, refresh) {
        // Keep the refresh rate if the new resolution supports it.
        if (!modes.some(m => m.width === width && m.height === height && m.refresh === refresh))
            refresh = Math.max.apply(null, modes.filter(m => m.width === width && m.height === height).map(m => m.refresh))
        Settings.setValue("display.mode", width + "x" + height + "@" + refresh)
        needsRestart = true
    }

    ListGroup {
        title: qsTr("Appearance")
        footer: qsTr("Automatic follows sunrise and sunset. Apps built for astraOS follow it too.")
        Item {
            width: parent.width
            height: 64
            SegmentedControl {
                anchors.centerIn: parent
                width: parent.width - 32
                model: [qsTr("Dark"), qsTr("Light"), qsTr("Automatic")]
                readonly property var modes: ["dark", "light", "auto"]
                currentIndex: Math.max(0, modes.indexOf(Settings.values["theme.mode"] || "dark"))
                onActivated: (i) => Settings.setValue("theme.mode", modes[i])
            }
        }
    }

    ListGroup {
        title: qsTr("Brightness")
        SliderRow {
            text: qsTr("Brightness")
            iconName: "brightness"
            value: System.brightness
            onMoved: (v) => System.setBrightness(Math.max(0.02, v))
        }
        SwitchRow {
            text: qsTr("Night light")
            subtitle: qsTr("Tints the screen amber to ease your eyes at night.")
            iconName: "night"
            key: "display.night_light"
            separator: !!Settings.values["display.night_light"]
        }
        SliderRow {
            visible: !!Settings.values["display.night_light"]
            height: visible ? 84 : 0
            text: qsTr("Warmth")
            key: "display.night_light_strength"
            fallback: 0.5
            separator: false
        }
    }

    ListGroup {
        title: qsTr("Screen")
        footer: page.modes.length === 0 ? qsTr("The display modes could not be read from the panel.") : ""
        ListItem {
            text: qsTr("Refresh rate")
            value: page.current.refresh ? page.current.refresh + " Hz" : "—"
            chevron: page.refreshRates.length > 1
            enabled: page.refreshRates.length > 1
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Refresh rate"),
                current: page.current.refresh,
                popOnPick: true,
                footer: qsTr("A higher refresh rate makes motion smoother and uses more battery."),
                options: page.refreshRates.map(r => ({ value: r, label: r + " Hz" }))
            }).picked.connect((r) => page.setMode(page.current.width, page.current.height, r))
        }
        ListItem {
            text: qsTr("Resolution")
            value: page.current.width ? page.current.width + " × " + page.current.height : "—"
            chevron: page.resolutions.length > 1
            enabled: page.resolutions.length > 1
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Resolution"),
                current: page.current.width + "x" + page.current.height,
                popOnPick: true,
                footer: qsTr("A lower resolution saves battery."),
                options: page.resolutions.map(r => ({ value: r.width + "x" + r.height, label: r.width + " × " + r.height,
                                                      subtitle: r.width >= 1080 ? "FHD+" : r.width >= 720 ? "HD+" : "" }))
            }).picked.connect((v) => {
                const p = v.split("x")
                page.setMode(+p[0], +p[1], page.current.refresh)
            })
        }
        ListItem {
            text: qsTr("Display size")
            subtitle: qsTr("Makes everything on screen bigger or smaller.")
            value: Math.round(Number(Settings.values["display.ui_scale"] ?? 1) * 100) + "%"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Display size"),
                key: "display.ui_scale",
                options: [ { value: 0.85, label: qsTr("Small") }, { value: 1, label: qsTr("Default") },
                           { value: 1.1, label: qsTr("Large") }, { value: 1.2, label: qsTr("Larger") } ]
            }).picked.connect(() => page.needsRestart = true)
        }
        ListItem {
            text: qsTr("Text size")
            value: Math.round(Theme.fontScale * 100) + "%"
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Text size"),
                key: "display.font_scale",
                options: [ { value: 0.9, label: qsTr("Small") }, { value: 1, label: qsTr("Default") },
                           { value: 1.15, label: qsTr("Large") }, { value: 1.3, label: qsTr("Largest") } ]
            })
        }
    }

    Card {
        visible: page.needsRestart
        accented: true
        Column {
            width: parent.width
            spacing: 12
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("Restart the system UI to apply the new display settings. Open apps will close.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: "white"
            }
            Button {
                text: qsTr("Restart now")
                primary: false
                onClicked: System.power("restart-sysboard")
            }
        }
    }

    ListGroup {
        title: qsTr("Lock")
        ListItem {
            text: qsTr("Screen timeout")
            readonly property int seconds: Number(Settings.values["display.screen_timeout"] ?? 60)
            value: seconds <= 0 ? qsTr("Never") : seconds < 60 ? qsTr("%1 seconds").arg(seconds) : qsTr("%n minutes", "", seconds / 60)
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Screen timeout"),
                key: "display.screen_timeout",
                options: [ { value: 15, label: qsTr("15 seconds") }, { value: 30, label: qsTr("30 seconds") },
                           { value: 60, label: qsTr("1 minute") }, { value: 120, label: qsTr("2 minutes") },
                           { value: 300, label: qsTr("5 minutes") }, { value: 600, label: qsTr("10 minutes") },
                           { value: 0, label: qsTr("Never") } ]
            })
        }
    }
}
