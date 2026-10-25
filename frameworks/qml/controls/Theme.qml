// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick

// astraOS design tokens. Measurements are in logical pixels on a ~393 px
// wide screen (the reference size of the design concepts).
QtObject {
    readonly property string fontFamily: "Poppins"

    // Palette
    readonly property color background: "#000000"
    readonly property color surface: "#141414"
    readonly property color surfaceRaised: "#1E1E1E"
    readonly property color separator: "#262626"
    readonly property color text: "#FFFFFF"
    readonly property color textSecondary: Qt.rgba(1, 1, 1, 0.68)
    readonly property color textTertiary: Qt.rgba(1, 1, 1, 0.45)
    readonly property color accent: "#FF7A00"          // switches, selections
    readonly property color highlight: "#FF0A8E"       // Control Center toggles
    readonly property color danger: "#FF453A"
    readonly property color switchOff: "#5E5E5E"
    readonly property color glass: Qt.rgba(0, 0, 0, 0.32)       // pills on wallpaper
    readonly property color glassStrong: Qt.rgba(0, 0, 0, 0.55)
    readonly property color glassButton: Qt.rgba(0, 0, 0, 0.82) // Control Center buttons

    // Type scale
    readonly property real largeTitleSize: 44
    readonly property real titleSize: 24
    readonly property real headlineSize: 17
    readonly property real bodySize: 15
    readonly property real captionSize: 13
    readonly property real footnoteSize: 11

    // Metrics
    readonly property real statusBarHeight: 47
    readonly property real homeIndicatorHeight: 30
    readonly property real margin: 14
    readonly property real cardRadius: 20
    readonly property real rowHeight: 56
    readonly property real iconRadiusRatio: 0.225 // app icon corner radius / size
}
