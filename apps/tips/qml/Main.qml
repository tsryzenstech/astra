// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Tips: swipe through what astraOS can do; some tips open the right place.
Rectangle {
    id: app
    color: Theme.background

    readonly property var tips: [
        { icon: "recents", colors: ["#7B2FF7", "#2F80FF"], title: qsTr("Recent apps"),
          text: qsTr("Swipe up from the bar at the bottom and hold for a moment to see the apps running in the background. Swipe a card up to close it.") },
        { icon: "sliders", colors: ["#FF2D8E", "#FF7A00"], title: qsTr("Control Center"),
          text: qsTr("Pull down from the top right corner. Hold the music player, Wi-Fi or Bluetooth to open their menus."),
          page: "controlcenter", label: qsTr("Choose the controls") },
        { icon: "notification", colors: ["#00C9A7", "#2F80FF"], title: qsTr("Notifications"),
          text: qsTr("Pull down from the top left corner. Swipe sideways to jump to Control Center.") },
        { icon: "image", colors: ["#FFB020", "#FF453A"], title: qsTr("Screenshots"),
          text: qsTr("Press power and volume down together. Tap the preview to draw on it, crop it or delete it.") },
        { icon: "grid", colors: ["#34D058", "#00C9B1"], title: qsTr("Your home screen"),
          text: qsTr("Hold an app to open its menu, or drag it to rearrange. Other icons make room for it.") },
        { icon: "lock", colors: ["#5B6B82", "#2F80FF"], title: qsTr("Lock screen"),
          text: qsTr("Hold the lock screen to change the clock font and widgets."), page: "lockscreen", label: qsTr("Customise") },
        { icon: "palette", colors: ["#FF2D8E", "#8B5CFF"], title: qsTr("Make it yours"),
          text: qsTr("Pick an accent colour and a wallpaper in Settings."), page: "display", pkg: "com.astra.themes", label: qsTr("Open Themes") },
        { icon: "code", colors: ["#111111", "#3A3A44"], title: qsTr("For developers"),
          text: qsTr("Tap Architecture seven times in About > More Settings to turn on Developer Options and USB debugging with ADU.") }
    ]

    Text {
        x: 20
        y: Theme.statusBarHeight + 16
        text: qsTr("Tips")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.largeTitleSize
        font.weight: Font.DemiBold
        color: Theme.text
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: Theme.statusBarHeight + 90
        anchors.bottomMargin: 90
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 30
        preferredHighlightEnd: width - 30
        spacing: 14
        leftMargin: 30
        rightMargin: 30
        model: app.tips
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            width: list.width - 60
            height: list.height
            radius: Theme.sheetRadius
            scale: index === list.currentIndex ? 1 : 0.92
            Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
            gradient: Gradient {
                GradientStop { position: 0; color: card.modelData.colors[0] }
                GradientStop { position: 1; color: card.modelData.colors[1] }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.18
                width: 128; height: 128; radius: 64
                color: Qt.rgba(1, 1, 1, 0.18)
                Icon { anchors.centerIn: parent; name: card.modelData.icon; size: 62 }
                SequentialAnimation on y {
                    running: card.index === list.currentIndex
                    loops: Animation.Infinite
                    NumberAnimation { to: card.height * 0.18 - 8; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: card.height * 0.18; duration: 1400; easing.type: Easing.InOutSine }
                }
            }
            Column {
                x: 26
                width: parent.width - 52
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 30
                spacing: 12
                Text { width: parent.width; text: card.modelData.title; wrapMode: Text.Wrap; font.family: Theme.fontFamily
                       font.pixelSize: 28; font.weight: Font.Bold; color: "white" }
                Text { width: parent.width; text: card.modelData.text; wrapMode: Text.Wrap; font.family: Theme.fontFamily
                       font.pixelSize: Theme.bodySize; color: Qt.rgba(1, 1, 1, 0.92); lineHeight: 1.15 }
                Button {
                    visible: !!card.modelData.label
                    primary: false
                    text: card.modelData.label || ""
                    onClicked: Packages.launch(card.modelData.pkg || "com.astra.settings", card.modelData.pkg ? {} : { page: card.modelData.page })
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 50
        spacing: 8
        Repeater {
            model: app.tips.length
            delegate: Rectangle {
                required property int index
                width: index === list.currentIndex ? 22 : 8
                height: 8
                radius: 4
                color: index === list.currentIndex ? Theme.accent : Theme.switchOff
                Behavior on width { SpringNumberAnimation { preset: Motion.bouncy } }
            }
        }
    }
}
