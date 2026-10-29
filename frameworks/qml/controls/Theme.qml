// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick
import Astra.Core

// astraOS design tokens (docs/DESIGN.md). Measurements are in logical
// pixels on a ~393 px wide screen (the reference size of the design
// concepts). Nothing in the system has a sharp corner: every surface uses
// one of the radii below.
QtObject {
    id: theme

    readonly property string fontFamily: "Poppins"

    // Accent palette. The user picks one in Settings > Display & Brightness.
    readonly property var accents: [
        { id: "orange", name: QT_TR_NOOP("Orange"), color: "#FF7A00", deep: "#FF3D00" },
        { id: "pink",   name: QT_TR_NOOP("Pink"),   color: "#FF2D8E", deep: "#D4006A" },
        { id: "violet", name: QT_TR_NOOP("Violet"), color: "#8B5CFF", deep: "#5B2BE0" },
        { id: "blue",   name: QT_TR_NOOP("Blue"),   color: "#2F80FF", deep: "#1450D8" },
        { id: "teal",   name: QT_TR_NOOP("Teal"),   color: "#00C9B1", deep: "#008F86" },
        { id: "green",  name: QT_TR_NOOP("Green"),  color: "#34D058", deep: "#16A34A" },
        { id: "red",    name: QT_TR_NOOP("Red"),    color: "#FF4D4D", deep: "#D92A2A" }
    ]
    readonly property string accentId: Settings.values["theme.accent"] || "orange"
    readonly property var accentEntry: {
        for (var i = 0; i < accents.length; ++i)
            if (accents[i].id === accentId)
                return accents[i]
        return accents[0]
    }

    // Appearance: Settings > Display > "theme.mode" = dark | light | auto
    // (auto: light between sunrise and sunset, from the weather forecast, or
    // 07:00-19:00). Every app built with Astra.Controls follows it.
    readonly property string mode: Settings.values["theme.mode"] || "dark"
    property date clock: new Date()
    property Timer ticker: Timer { interval: 60000; running: theme.mode === "auto"; repeat: true; onTriggered: theme.clock = new Date() }
    readonly property bool light: {
        if (mode === "light")
            return true
        if (mode !== "auto")
            return false
        const w = Weather.current
        const day = w && w.daily && w.daily.length ? w.daily[0] : null
        const hm = (s, fallback) => s ? Number(s.substring(11, 13)) * 60 + Number(s.substring(14, 16)) : fallback
        const now = clock.getHours() * 60 + clock.getMinutes()
        return now >= hm(day ? day.sunrise : "", 7 * 60) && now < hm(day ? day.sunset : "", 19 * 60)
    }
    readonly property bool dark: !light

    // Palette
    readonly property color background: light ? "#F2F2F7" : "#000000"
    readonly property color surface: light ? "#FFFFFF" : "#151517"
    readonly property color surfaceRaised: light ? "#E6E6EB" : "#202024"
    readonly property color surfacePressed: light ? "#D6D6DC" : "#2A2A30"
    readonly property color separator: light ? "#DCDCE1" : "#2A2A2E"
    readonly property color text: light ? "#0B0B0F" : "#FFFFFF"
    readonly property color textSecondary: light ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(1, 1, 1, 0.68)
    readonly property color textTertiary: light ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color accentText: "#FFFFFF"            // text and icons on accent colours
    readonly property color sheet: light ? "#FFFFFF" : "#1C1C20"   // dialogs, bottom sheets
    readonly property color glassPanel: light ? Qt.rgba(0.96, 0.96, 0.98, 0.82) : Qt.rgba(0.1, 0.1, 0.12, 0.82)
    readonly property color accent: accentEntry.color      // switches, selections, primary buttons
    readonly property color accentDeep: accentEntry.deep   // second stop of accent gradients
    readonly property color highlight: "#FF0A8E"           // Control Center toggles
    readonly property color success: "#34D058"
    readonly property color warning: "#FFB020"
    readonly property color danger: "#FF453A"
    readonly property color switchOff: light ? "#D1D1D6" : "#4A4A50"
    readonly property color glass: Qt.rgba(0, 0, 0, 0.32)       // pills on wallpaper
    readonly property color glassStrong: Qt.rgba(0, 0, 0, 0.55)
    readonly property color glassButton: Qt.rgba(0, 0, 0, 0.82) // Control Center buttons
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.45)

    // Type scale, multiplied by the user's text size.
    readonly property real fontScale: Math.max(0.8, Math.min(1.4, Number(Settings.values["display.font_scale"] || 1)))
    function font(size) { return Math.round(size * fontScale) }
    readonly property int largeTitleSize: font(40)
    readonly property int titleSize: font(24)
    readonly property int headlineSize: font(17)
    readonly property int bodySize: font(15)
    readonly property int captionSize: font(13)
    readonly property int footnoteSize: font(11)

    // Metrics
    readonly property real statusBarHeight: 47
    readonly property real homeIndicatorHeight: 30
    readonly property real margin: 16
    readonly property real spacing: 10
    readonly property real rowHeight: 58

    // Radii
    readonly property real radiusSmall: 12   // chips, small buttons, text fields
    readonly property real radius: 18        // list rows, tiles
    readonly property real cardRadius: 26    // cards and groups
    readonly property real sheetRadius: 34   // dialogs, panels, bottom sheets
    readonly property real screenRadius: 44  // apps while they open, close or are listed in Recents
    readonly property real iconRadiusRatio: 0.30 // app icon corner radius / size

    // Motion (Astra.Animation springs)
    readonly property real springSnappy: 5.2
    readonly property real springBouncy: 3.6
    readonly property real dampingBouncy: 0.62
    readonly property real dampingCalm: 0.86
}
