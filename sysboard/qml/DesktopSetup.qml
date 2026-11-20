// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// First start of astraOS Desktop, full screen: hello, language, Wi-Fi, the user (name and password),
// AstraID (optional; Market, PetalDrop and Phone Linker use it), appearance and a word about the
// phone. "setup.done" turns it off for good (Settings > Reset brings it back).
Rectangle {
    id: root
    signal finished()
    focus: true

    readonly property bool needed: Settings.ready && Settings.values["setup.done"] !== true
    readonly property var steps: ["hello", "language", "wifi", "user", "astraid", "appearance", "phone", "done"]
    property int step: 0
    readonly property string current: steps[step]
    readonly property var wifi: Network.state.wifi || ({})
    readonly property real k: Math.max(0.9, Math.min(1.6, height / 720))
    property bool userReady: false

    function next() {
        let s = step + 1
        while (s < steps.length - 1 && steps[s] === "wifi" && !wifi.available)
            s++
        step = Math.min(steps.length - 1, s)
        page.value = 0.0
        page.animateTo(1, 0)
    }
    function back() { if (step > 0) { step--; page.value = 0; page.animateTo(1, 0) } }
    function finish() {
        Settings.setValue("setup.done", true)
        root.finished()
    }
    readonly property bool canContinue: current !== "user" || userReady

    color: "black"
    visible: needed || fade.running
    opacity: needed ? 1 : 0
    Behavior on opacity { NumberAnimation { id: fade; duration: 500 } }
    MouseArea { anchors.fill: parent }   // nothing below while setting up

    Spring { id: page; to: 1; response: 0.5; dampingFraction: 0.86 }

    Image {
        id: backdrop
        anchors.fill: parent
        source: Host.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(width, height)
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: backdrop
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: root.current === "hello" ? 0 : 0.8
        Behavior on blur { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.current === "hello" ? 0.10 : 0.40) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.current === "hello" ? 0.45 : 0.58) }
        }
    }

    // Where we are.
    Row {
        visible: root.current !== "hello" && root.current !== "done"
        anchors.horizontalCenter: parent.horizontalCenter
        y: 34 * root.k
        spacing: 8
        Repeater {
            model: root.steps.length - 2
            Rectangle {
                required property int index
                width: index + 1 === root.step ? 24 : 7
                height: 7
                radius: 3.5
                color: "white"
                opacity: index + 1 <= root.step ? 0.95 : 0.3
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: column
        width: 520 * root.k
        height: parent.height - 160 * root.k
        anchors.horizontalCenter: parent.horizontalCenter
        y: 80 * root.k
        opacity: page.value
        transform: Translate { x: (1 - page.value) * 60 }

        // ---- hello ----
        Column {
            visible: root.current === "hello"
            anchors.centerIn: parent
            spacing: 18
            Text {
                id: hello
                anchors.horizontalCenter: parent.horizontalCenter
                property int i: 0
                readonly property var words: ["Hello", "Ciao", "Hola", "Bonjour", "Hallo", "Olá", "こんにちは", "你好", "Привет", "مرحبا"]
                text: words[i]
                font.family: Theme.fontFamily
                font.pixelSize: 110 * root.k
                font.weight: Font.Light
                color: "white"
                Timer { interval: 1800; repeat: true; running: root.visible && root.current === "hello"; onTriggered: swap.restart() }
                SequentialAnimation {
                    id: swap
                    NumberAnimation { target: hello; property: "opacity"; to: 0; duration: 220 }
                    ScriptAction { script: hello.i = (hello.i + 1) % hello.words.length }
                    NumberAnimation { target: hello; property: "opacity"; to: 1; duration: 320 }
                }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Welcome to astraOS"); font.family: Theme.fontFamily; font.pixelSize: 24 * root.k; color: Qt.rgba(1, 1, 1, 0.85) }
        }

        // ---- language ----
        Column {
            visible: root.current === "language"
            width: parent.width
            spacing: 12
            Title { text: qsTr("Language") }
            ListView {
                width: parent.width
                height: Math.min(contentHeight, column.height - 120)
                clip: true
                spacing: 10
                model: Language.available
                delegate: Choice {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.name
                    selected: Language.current === modelData.code
                    onClicked: Language.set(modelData.code)
                }
            }
        }

        // ---- Wi-Fi ----
        Column {
            visible: root.current === "wifi"
            width: parent.width
            spacing: 12
            Title { text: qsTr("Wi-Fi") }
            Subtitle { text: qsTr("Choose a network to set up your computer and get the latest updates.") }
            Choice {
                text: qsTr("Wi-Fi")
                switchable: true
                selected: !!root.wifi.powered
                onClicked: Network.call("wifiSetPowered", { on: !root.wifi.powered }, null)
            }
            ListView {
                width: parent.width
                height: Math.min(contentHeight, column.height - 260)
                clip: true
                spacing: 10
                model: root.wifi.powered ? (root.wifi.networks || []) : []
                delegate: Choice {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.ssid
                    detail: modelData.connected ? qsTr("Connected") : modelData.security !== "open" ? qsTr("Secured") : ""
                    selected: !!modelData.connected
                    onClicked: {
                        if (modelData.connected) return
                        if (modelData.security === "open" || modelData.known)
                            Network.call("wifiConnect", { id: modelData.id }, null)
                        else
                            wifiPassword.ask(modelData)
                    }
                }
            }
            Field {
                id: wifiPassword
                property var net: null
                function ask(n) { net = n; visible = true; text = ""; forceActiveFocus() }
                visible: false
                secret: true
                placeholder: qsTr("Password for %1").arg(net ? net.ssid : "")
                onAccepted: {
                    Network.call("wifiConnect", { id: net.id, passphrase: text }, null)
                    visible = false
                }
            }
        }

        // ---- the user ----
        Column {
            visible: root.current === "user"
            width: parent.width
            spacing: 12
            Title { text: qsTr("Your account") }
            Subtitle { text: qsTr("The name on the lock screen, and the password that unlocks this computer.") }
            Field { id: userName; placeholder: qsTr("Name"); text: Settings.values["desktop.user.name"] || ""
                    onTextChanged: root.userReady = Lock.hasPin }
            Field { id: userPassword; visible: !Lock.hasPin; placeholder: qsTr("Password (at least 4 characters)"); secret: true }
            Field { id: userPassword2; visible: !Lock.hasPin; placeholder: qsTr("Password again"); secret: true; onAccepted: createUser.clicked() }
            Text { id: userError; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap; color: "#FF6B6B"; font.family: Theme.fontFamily; font.pixelSize: 13 }
            Button {
                id: createUser
                visible: !Lock.hasPin
                text: qsTr("Create")
                enabled: userName.text.trim() !== "" && userPassword.text.length >= 4
                onClicked: {
                    if (userPassword.text !== userPassword2.text) {
                        userError.text = qsTr("The passwords are not the same.")
                        return
                    }
                    Settings.setValue("desktop.user.name", userName.text.trim())
                    Lock.setPin("", userPassword.text, (ok, error) => {
                        userError.text = ok ? "" : (error || "")
                        if (ok) { root.userReady = true; root.next() }
                    })
                }
            }
            Text {
                visible: Lock.hasPin
                text: qsTr("Password set.")
                font.family: Theme.fontFamily; font.pixelSize: 15; color: Qt.rgba(1, 1, 1, 0.8)
                Component.onCompleted: root.userReady = Lock.hasPin
            }
        }

        // ---- AstraID ----
        Column {
            visible: root.current === "astraid"
            width: parent.width
            spacing: 12
            Title { text: Account.state.signedIn ? qsTr("Signed In") : qsTr("AstraID") }
            Subtitle {
                text: Account.state.signedIn ? Account.state.email
                    : qsTr("Sign in to download apps from Market, share with PetalDrop and link your phone with Phone Linker. You can do it later in Settings.")
            }
            Column {
                visible: !Account.state.signedIn
                width: parent.width
                spacing: 10
                Field { id: email; placeholder: qsTr("Email") }
                Field { id: password; placeholder: qsTr("Password"); secret: true }
                Text { id: accountError; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap; color: "#FF6B6B"; font.family: Theme.fontFamily; font.pixelSize: 13 }
                Row {
                    spacing: 10
                    Button { text: qsTr("Sign In"); onClicked: Account.call("signIn", { email: email.text, password: password.text, deviceType: "desktop" }, (r, e) => accountError.text = e || "") }
                    Button { text: qsTr("Create AstraID"); primary: false
                             onClicked: Account.call("signIn", { email: email.text, password: password.text, register: true, deviceType: "desktop" }, (r, e) => accountError.text = e || "") }
                }
            }
        }

        // ---- appearance ----
        Column {
            visible: root.current === "appearance"
            width: parent.width
            spacing: 14
            Title { text: qsTr("Appearance") }
            Row {
                spacing: 14
                Repeater {
                    model: [{ id: "light", label: qsTr("Light"), bg: "#F2F2F7", fg: "#0B0B0F" },
                            { id: "dark", label: qsTr("Dark"), bg: "#1C1C1E", fg: "white" },
                            { id: "auto", label: qsTr("Automatic"), bg: "#6E6E73", fg: "white" }]
                    delegate: Column {
                        id: look
                        required property var modelData
                        spacing: 8
                        Rectangle {
                            width: (column.width - 28) / 3
                            height: width * 0.66
                            radius: 18
                            color: look.modelData.bg
                            border.width: (Settings.values["theme.mode"] || "auto") === look.modelData.id ? 3 : 0
                            border.color: Theme.accent
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater { model: 3; Rectangle { width: 60; height: 8; radius: 4; color: look.modelData.fg; opacity: 0.4 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Settings.setValue("theme.mode", look.modelData.id) }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: look.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 14; color: "white" }
                    }
                }
            }
        }

        // ---- the phone ----
        Column {
            visible: root.current === "phone"
            width: parent.width
            spacing: 12
            Title { text: qsTr("Your phone") }
            Subtitle { text: qsTr("With Phone Linker your contacts, photos and notifications follow you between this computer and your phone, as they happen. Turn it on in Settings > Phone Linker, signed in with the same AstraID on both.") }
        }

        // ---- done ----
        Column {
            visible: root.current === "done"
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("You're all set"); font.family: Theme.fontFamily; font.pixelSize: 44 * root.k; font.weight: Font.Bold; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Welcome to astraOS Desktop."); font.family: Theme.fontFamily; font.pixelSize: 18 * root.k; color: Qt.rgba(1, 1, 1, 0.7) }
        }
    }

    // ---- navigation ----
    Rectangle {
        visible: root.step > 0 && root.current !== "done"
        x: 28; y: 28
        width: 42; height: 42; radius: 21
        color: Qt.rgba(1, 1, 1, backArea.pressed ? 0.28 : 0.16)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        Icon { anchors.centerIn: parent; name: "chevron-left"; size: 20; color: "white" }
        MouseArea { id: backArea; anchors.fill: parent; anchors.margins: -6; onClicked: root.back() }
    }
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 * root.k
        anchors.horizontalCenter: parent.horizontalCenter
        width: 340 * root.k
        spacing: 10
        Rectangle {
            width: parent.width
            height: 52
            radius: 26
            opacity: root.canContinue ? 1 : 0.4
            color: Qt.rgba(1, 1, 1, nextArea.pressed ? 0.8 : 1)
            Text {
                anchors.centerIn: parent
                text: root.current === "hello" ? qsTr("Get Started") : root.current === "done" ? qsTr("Start Using astraOS") : qsTr("Continue")
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: "#0B0B0F"
            }
            MouseArea { id: nextArea; anchors.fill: parent; enabled: root.canContinue; onClicked: root.current === "done" ? root.finish() : root.next() }
        }
        Item {
            width: parent.width
            height: 24
            Text {
                visible: root.current === "astraid" && !Account.state.signedIn
                anchors.centerIn: parent
                text: qsTr("Set Up Later")
                font.family: Theme.fontFamily
                font.pixelSize: 16
                color: Qt.rgba(1, 1, 1, 0.8)
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.next() }
            }
        }
    }
    Keys.onReturnPressed: if (root.canContinue && !(root.current === "user" && !Lock.hasPin)) root.current === "done" ? root.finish() : root.next()

    component Title: Text { font.family: Theme.fontFamily; font.pixelSize: 38 * root.k; font.weight: Font.Bold; color: "white"; width: parent ? parent.width : 300; wrapMode: Text.WordWrap }
    component Subtitle: Text { font.family: Theme.fontFamily; font.pixelSize: 16; color: Qt.rgba(1, 1, 1, 0.7); width: parent ? parent.width : 300; wrapMode: Text.WordWrap }
    component Choice: Rectangle {
        id: choice
        property string text
        property string detail
        property bool selected: false
        property bool switchable: false
        signal clicked()
        width: parent ? parent.width : 300
        height: 56
        radius: 20
        color: Qt.rgba(1, 1, 1, area.pressed ? 0.24 : area.containsMouse ? 0.19 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: choice.text; font.family: Theme.fontFamily; font.pixelSize: 16; color: "white" }
        Text { visible: !choice.switchable && choice.detail !== ""; anchors.right: parent.right; anchors.rightMargin: 46; anchors.verticalCenter: parent.verticalCenter; text: choice.detail; font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.6) }
        Icon { visible: !choice.switchable && choice.selected; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 20; color: Theme.accent }
        Switch { visible: choice.switchable; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; checked: choice.selected; enabled: false }
        MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: choice.clicked() }
    }
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder
        property bool secret: false
        signal accepted()
        width: parent ? parent.width : 300
        height: 54
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: input.activeFocus ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(1, 1, 1, 0.16)
        function forceActiveFocus() { input.forceActiveFocus() }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            verticalAlignment: TextInput.AlignVCenter
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: Qt.ImhNoAutoUppercase
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: "white"
            onAccepted: field.accepted()
            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !parent.text; text: field.placeholder; font: parent.font; color: Qt.rgba(1, 1, 1, 0.45) }
        }
    }
}
