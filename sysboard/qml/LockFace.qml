// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// A lock screen drawn from one of the user's lock screens (LockSlots): the wallpaper, the date, the
// clock in its font, weight and height, and the widgets. The real lock screen shows the current one;
// the picker shows each as a small card; the editor shows the one being changed, with boxes around the
// parts and a handle to stretch the clock.
Item {
    id: root

    property var slot: LockSlots.current
    property bool editing: false
    property bool showLock: true
    // Clock height: 1 (normal) up to maxStretch. The box of the clock follows it.
    readonly property real maxStretch: 2.3
    property real stretch: Math.max(1, Math.min(maxStretch, Number(slot.stretch || 1)))
    readonly property real clockSize: 118
    readonly property real clockTop: 128
    readonly property real clockBoxHeight: clockSize * 1.12 * stretch
    readonly property real widgetsTop: clockTop + clockBoxHeight + 14
    readonly property alias clockBox: clockBoxItem
    readonly property alias widgetsBox: widgetsBoxItem

    readonly property var clockWeights: ({
        "Thin": Font.Thin, "ExtraLight": Font.ExtraLight, "Light": Font.Light, "Regular": Font.Normal,
        "Medium": Font.Medium, "SemiBold": Font.DemiBold, "Bold": Font.Bold, "ExtraBold": Font.ExtraBold,
        "Black": Font.Black
    })
    readonly property url wallpaperUrl: slot.wallpaper ? System.fileUrl(slot.wallpaper) : Host.wallpaper

    Image {
        anchors.fill: parent
        source: root.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width, height)
        asynchronous: true
    }

    Icon {
        visible: root.showLock
        name: "lock"
        size: 22
        anchors.horizontalCenter: parent.horizontalCenter
        y: 62
        opacity: 0.85
    }

    // The date, above the clock.
    Item {
        id: dateBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: 92
        width: dateText.implicitWidth + 36
        height: 34
        Text {
            id: dateText
            anchors.centerIn: parent
            text: SystemClock.longDate
            font.family: Theme.fontFamily
            font.pixelSize: 21
            color: "white"
        }
        Rectangle {
            visible: root.editing
            anchors.fill: parent
            radius: 17
            color: "transparent"
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.45)
        }
    }

    // The clock: its glyphs are stretched downwards, not just scaled, so a thin face grows tall.
    Item {
        id: clockBoxItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.clockTop
        width: Math.min(root.width - 24, time.implicitWidth + 40)
        height: root.clockBoxHeight

        Text {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            text: SystemClock.time
            font.family: root.slot.font || Theme.fontFamily
            font.pixelSize: root.clockSize
            font.weight: root.clockWeights[root.slot.weight || "SemiBold"] ?? Font.DemiBold
            font.letterSpacing: -3
            color: "white"
            transformOrigin: Item.Top
            transform: Scale { origin.x: time.width / 2; origin.y: 0; yScale: root.stretch }
        }
        Rectangle {
            visible: root.editing
            anchors.fill: parent
            radius: 22
            color: "transparent"
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.45)
        }
    }

    // The widgets.
    Item {
        id: widgetsBoxItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.widgetsTop
        width: Math.max(root.editing ? 4 * 53 + 3 * 9.5 + 24 : 0, widgetRow.width + 24)
        height: 53 + (root.editing ? 20 : 0)
        Row {
            id: widgetRow
            anchors.centerIn: parent
            spacing: 9.5
            Repeater {
                model: root.slot.widgets || []
                delegate: Item {
                    id: slotItem
                    required property var modelData
                    readonly property var info: Packages.count >= 0 ? Packages.widget(modelData) : ({})
                    readonly property bool wide: info.size === "wide"
                    visible: info.qmlUrl !== undefined
                    width: wide ? 53 * 2 + 9.5 : 53
                    height: 53
                    Rectangle { anchors.fill: parent; radius: 13; color: Qt.rgba(0, 0, 0, 0.36) }
                    Loader { anchors.fill: parent; anchors.margins: 6; source: slotItem.info.qmlUrl || "" }
                }
            }
        }
        Rectangle {
            visible: root.editing
            anchors.fill: parent
            radius: 22
            color: "transparent"
            border.width: 1.5
            border.color: Qt.rgba(1, 1, 1, 0.45)
        }
    }
}
