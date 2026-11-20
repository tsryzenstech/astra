// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// The lock screen of astraOS Desktop: the lock screen the user chose (LockSlots: wallpaper, clock font,
// weight, height, the same ones as on the phone, picked and edited in the same way; no widgets on the desktop), with the
// user and a password field below. With music playing the pill takes the place of the user until a
// key is pressed or the screen clicked. Hold the screen for three seconds to change the lock screen.
Item {
    id: root

    property var shell
    property bool active: true
    property bool reveal: false
    property bool failed: false
    property bool busy: false
    readonly property bool passwordVisible: !MediaController.active || reveal
    readonly property var slot: LockSlots.current
    readonly property real k: Math.max(0.8, height / 720)
    property var pendingVerify: null
    readonly property var weights: ({
        "Thin": Font.Thin, "ExtraLight": Font.ExtraLight, "Light": Font.Light, "Regular": Font.Normal,
        "Medium": Font.Medium, "SemiBold": Font.DemiBold, "Bold": Font.Bold, "ExtraBold": Font.ExtraBold,
        "Black": Font.Black
    })
    readonly property real stretch: Math.max(1, Math.min(1.6, Number(slot.stretch || 1)))

    visible: active || exit.running || exit.value < 0.999
    focus: active

    function lock() {
        exit.snap(0)
        field.text = ""
        reveal = false
        failed = false
        pendingVerify = null
    }
    function finishUnlock() {
        field.text = ""
        exit.animateTo(1, 0)
        root.shell.unlocked(null)
    }
    // The password, then fn (the lock screen picker), with the screen staying locked.
    function verifyThen(fn) {
        if (!Lock.hasPin) {
            fn()
            return
        }
        pendingVerify = fn
        reveal = true
        field.forceActiveFocus()
    }

    Spring { id: exit; to: 0; response: 0.5; dampingFraction: 0.92 }
    // The recovery environment starts unlocked: nothing to show.
    Component.onCompleted: if (!active) exit.snap(1)
    // The screen lifts and fades away when the password is right.
    opacity: 1 - Math.max(0, Math.min(1, exit.value))
    transform: Translate { y: -root.height * 0.05 * Math.max(0, exit.value) }

    Image {
        anchors.fill: parent
        source: root.slot.wallpaper ? System.fileUrl(root.slot.wallpaper) : Host.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width, height)
        asynchronous: true
    }

    MouseArea {
        id: surface
        anchors.fill: parent
        onClicked: { root.reveal = true; field.forceActiveFocus() }
        onPressed: holdTimer.restart()
        onReleased: holdTimer.stop()
        onCanceled: holdTimer.stop()
        Timer {
            id: holdTimer
            interval: 3000
            onTriggered: if (root.active) root.verifyThen(() => root.shell.openLockPicker())
        }
    }

    Item {
        id: face
        anchors.fill: parent
        enabled: false

        Icon {
            name: "lock"
            size: 22 * root.k
            anchors.horizontalCenter: parent.horizontalCenter
            y: 46 * root.k
            opacity: 0.85
        }
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            y: 76 * root.k
            text: SystemClock.time
            font.family: root.slot.font || Theme.fontFamily
            font.pixelSize: 138 * root.k
            font.weight: root.weights[root.slot.weight || "SemiBold"] ?? Font.DemiBold
            font.letterSpacing: -4 * root.k
            color: "white"
            transformOrigin: Item.Top
            transform: Scale { origin.x: clock.width / 2; origin.y: 0; yScale: root.stretch }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: clock.y + clock.height * 0.96 * root.stretch + 2 * root.k
            text: SystemClock.longDate
            font.family: Theme.fontFamily
            font.pixelSize: 21 * root.k
            color: "white"
        }
    }

    // The user: avatar, name, password.
    Column {
        id: user
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 38 * root.k
        spacing: 10 * root.k
        opacity: root.passwordVisible ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 240 } }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 104 * root.k; height: width; radius: width / 2
            color: "white"
            clip: true
            Image {
                anchors.fill: parent
                visible: source !== ""
                source: Settings.values["desktop.user.avatar"] ? System.fileUrl(Settings.values["desktop.user.avatar"]) : ""
                fillMode: Image.PreserveAspectCrop
            }
            Icon {
                visible: !Settings.values["desktop.user.avatar"]
                anchors.centerIn: parent
                name: "person"
                size: 62 * root.k
                color: "#5F5F5F"
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Settings.values["desktop.user.name"] || Account.state.name || qsTr("User")
            font.family: Theme.fontFamily
            font.pixelSize: 19 * root.k
            font.weight: Font.DemiBold
            color: "white"
        }
        Item {
            width: 236 * root.k
            height: 40 * root.k
            anchors.horizontalCenter: parent.horizontalCenter
            Rectangle {
                id: box
                width: parent.width
                height: parent.height
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.42)
                border.width: root.failed ? 1.5 : 0
                border.color: "#FF453A"
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: box; property: "x"; to: -10; duration: 50 }
                    NumberAnimation { target: box; property: "x"; to: 10; duration: 80 }
                    NumberAnimation { target: box; property: "x"; to: -6; duration: 70 }
                    NumberAnimation { target: box; property: "x"; to: 0; duration: 60 }
                }
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 16 * root.k
                    anchors.rightMargin: 46 * root.k
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    font.family: Theme.fontFamily
                    font.pixelSize: 15 * root.k
                    color: "white"
                    enabled: root.active && !root.busy
                    onAccepted: root.submit()
                    onTextChanged: root.failed = false
                    Text {
                        visible: !field.text
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Password...")
                        font: field.font
                        color: Qt.rgba(1, 1, 1, 0.6)
                    }
                }
                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * root.k
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30 * root.k; height: width
                    Icon { anchors.centerIn: parent; name: "chevron-right"; size: 18 * root.k; color: "white"; opacity: field.text ? 1 : 0.7 }
                    MouseArea { anchors.fill: parent; onClicked: root.submit() }
                }
            }
        }
    }

    // Music, when something plays: the same pill as on the phone.
    MusicPill {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34 * root.k
        transformOrigin: Item.Bottom
        scale: 1.35 * root.k
        visible: MediaController.active && !root.reveal
        onExpandRequested: { root.reveal = true; field.forceActiveFocus() }
    }

    function submit() {
        if (busy)
            return
        if (!Lock.hasPin) {
            finishUnlock()
            return
        }
        busy = true
        Lock.verify(field.text, (ok, error) => {
            busy = false
            if (ok) {
                if (root.pendingVerify) {
                    const fn = root.pendingVerify
                    root.pendingVerify = null
                    field.text = ""
                    root.reveal = false
                    fn()
                } else {
                    root.finishUnlock()
                }
            } else {
                root.failed = true
                field.text = ""
                shake.restart()
            }
        })
    }

    // Any key brings up the password field.
    Keys.onPressed: (e) => {
        if (e.text.length > 0 || e.key === Qt.Key_Return) {
            reveal = true
            field.forceActiveFocus()
            if (e.text.length > 0 && e.key !== Qt.Key_Return && field.text === "")
                field.text = e.text
            e.accepted = true
        }
    }
    onActiveChanged: if (active) { reveal = false; field.forceActiveFocus() }
    // The keyboard works as soon as the lock screen is there (at the start there is no change of `active` to say so).
    Timer { running: root.active; interval: 500; repeat: false; onTriggered: field.forceActiveFocus() }
}
