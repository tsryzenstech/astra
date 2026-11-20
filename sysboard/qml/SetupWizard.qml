// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// First start: hello, language, Wi-Fi, mobile data, Bluetooth, location,
// AstraID (optional; Market needs it), screen lock PIN and appearance.
// "setup.done" turns it off for good (Settings > Reset brings it back).
Rectangle {
    id: root
    signal finished()
    // The height of the on-screen keyboard when it is up: the page makes room for it.
    property real keyboardInset: 0
    focus: true

    readonly property bool needed: Settings.ready && Settings.values["setup.done"] !== true
    readonly property var steps: ["hello", "language", "wifi", "mobile", "bluetooth", "location", "astraid", "pin", "appearance", "done"]
    property int step: 0
    readonly property string current: steps[step]
    readonly property var wifi: Network.state.wifi || ({})
    readonly property var cell: Network.state.cellular || ({})
    readonly property var bt: Network.state.bluetooth || ({})

    // Puts the keyboard away: a step that was typing in a field does not keep it open.
    function dismissKeyboard() {
        root.forceActiveFocus()
        Qt.inputMethod.hide()
    }

    function next() {
        dismissKeyboard()
        let s = step + 1
        // Hardware that isn't there is skipped.
        while (s < steps.length - 1 && ((steps[s] === "wifi" && !wifi.available) || (steps[s] === "mobile" && !cell.available)
                                        || (steps[s] === "bluetooth" && !bt.available)))
            s++
        step = Math.min(steps.length - 1, s)
        page.value = 0.0
        page.animateTo(1, 0)
    }
    function back() { dismissKeyboard(); if (step > 0) { step--; page.value = 0; page.animateTo(1, 0) } }
    function finish() {
        Settings.setValue("setup.done", true)
        root.finished()
    }

    color: "black"
    visible: needed || fade.running
    opacity: needed ? 1 : 0
    Behavior on opacity { NumberAnimation { id: fade; duration: 500 } }
    MouseArea { anchors.fill: parent }   // nothing below while setting up

    Spring { id: page; to: 1; response: 0.5; dampingFraction: 0.86 }

    // The wallpaper of the phone behind everything: sharp on the first page, then frosted, with a
    // slow drift so the screen is never still.
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
        saturation: root.current === "hello" ? 0.1 : 0.0
        Behavior on blur { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, root.current === "hello" ? 0.10 : 0.40) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, root.current === "hello" ? 0.45 : 0.58) }
        }
    }

    // Where we are: a row of dots.
    Row {
        visible: root.current !== "hello" && root.current !== "done"
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.statusBarHeight + 22
        spacing: 7
        Repeater {
            model: root.steps.length - 2
            Rectangle {
                required property int index
                width: index + 1 === root.step ? 20 : 6
                height: 6
                radius: 3
                color: "white"
                opacity: index + 1 <= root.step ? 0.95 : 0.3
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: Theme.statusBarHeight + 70
        anchors.bottomMargin: root.keyboardInset > 0 ? root.keyboardInset + 12 : 150
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        opacity: page.value
        transform: Translate { x: (1 - page.value) * 60 }

        // ---- hello ------------------------------------------------------------
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
                font.pixelSize: 84
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
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Welcome to astraOS"); font.family: Theme.fontFamily; font.pixelSize: 20; color: Qt.rgba(1, 1, 1, 0.85) }
        }

        // ---- language -----------------------------------------------------------
        Column {
            visible: root.current === "language"
            x: 24; width: parent.width - 48
            spacing: 14
            Title { text: qsTr("Language") }
            Repeater {
                model: Language.available
                delegate: Choice {
                    required property var modelData
                    text: modelData.name
                    selected: Language.current === modelData.code
                    onClicked: Language.set(modelData.code)
                }
            }
        }

        // ---- Wi-Fi ----------------------------------------------------------------
        Column {
            visible: root.current === "wifi"
            x: 24; width: parent.width - 48
            spacing: 12
            Title { text: qsTr("Wi-Fi") }
            Subtitle { text: qsTr("Choose a network to set up your phone and get the latest updates.") }
            Choice {
                text: qsTr("Wi-Fi")
                switchable: true
                selected: !!root.wifi.powered
                onClicked: Network.call("wifiSetPowered", { on: !root.wifi.powered }, null)
            }
            ListView {
                width: parent.width
                height: Math.min(contentHeight, root.keyboardInset > 0 ? 96 : root.height * 0.42)
                clip: true
                spacing: 8
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
            Rectangle {
                id: wifiPassword
                property var net: null
                function ask(n) { net = n; visible = true; pw.text = ""; pw.forceActiveFocus() }
                visible: false
                width: parent.width
                height: 58
                radius: 20
                color: Qt.rgba(1, 1, 1, 0.14)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.16)
                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                    color: "white"
                    onAccepted: {
                        Network.call("wifiConnect", { id: wifiPassword.net.id, passphrase: text }, null)
                        wifiPassword.visible = false
                        root.dismissKeyboard()
                    }
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !parent.text; text: qsTr("Password for %1").arg(wifiPassword.net ? wifiPassword.net.ssid : ""); font: parent.font; color: Qt.rgba(1, 1, 1, 0.45) }
                }
            }
        }

        // ---- mobile data ----------------------------------------------------------
        Column {
            visible: root.current === "mobile"
            x: 24; width: parent.width - 48
            spacing: 12
            Title { text: qsTr("Mobile Data") }
            Subtitle {
                text: !root.cell.simPresent ? qsTr("No SIM card. You can insert one later.")
                    : qsTr("%1 • %2").arg(root.cell.operator || qsTr("SIM")).arg(root.cell.technology || "")
            }
            Choice {
                visible: !!root.cell.simPresent
                text: qsTr("Use Mobile Data")
                switchable: true
                selected: !!root.cell.dataEnabled
                onClicked: Network.call("cellSetData", { on: !root.cell.dataEnabled }, null)
            }
        }

        // ---- Bluetooth ------------------------------------------------------------
        Column {
            visible: root.current === "bluetooth"
            x: 24; width: parent.width - 48
            spacing: 12
            Title { text: qsTr("Bluetooth") }
            Subtitle { text: qsTr("For headphones, speakers, watches and your car.") }
            Choice {
                text: qsTr("Bluetooth")
                switchable: true
                selected: !!root.bt.powered
                onClicked: Network.call("btSetPowered", { on: !root.bt.powered }, null)
            }
        }

        // ---- location -------------------------------------------------------------
        Column {
            visible: root.current === "location"
            x: 24; width: parent.width - 48
            spacing: 12
            Title { text: qsTr("Location Services") }
            Subtitle { text: qsTr("Maps, Weather and Find My Device use where the phone is. Apps always ask you first.") }
            Choice {
                text: qsTr("Location Services")
                switchable: true
                selected: Settings.values["controls.location"] !== false
                onClicked: Settings.setValue("controls.location", Settings.values["controls.location"] === false)
            }
        }

        // ---- AstraID --------------------------------------------------------------
        Column {
            visible: root.current === "astraid"
            x: 24; width: parent.width - 48
            spacing: 12
            Title { text: Account.state.signedIn ? qsTr("Signed In") : qsTr("AstraID") }
            Subtitle {
                text: Account.state.signedIn ? Account.state.email
                    : qsTr("Sign in to download apps from Market, find your phone and back up your contacts. You can do it later in Settings.")
            }
            Column {
                visible: !Account.state.signedIn
                width: parent.width
                spacing: 10
                Field { id: email; placeholder: qsTr("Email") ; hints: Qt.ImhEmailCharactersOnly }
                Field { id: password; placeholder: qsTr("Password"); secret: true }
                Text { id: accountError; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap; color: "#FF6B6B"; font.family: Theme.fontFamily; font.pixelSize: 13 }
                Row {
                    spacing: 10
                    Button {
                        text: qsTr("Sign In")
                        onClicked: Account.call("signIn", { email: email.text, password: password.text }, (r, e) => accountError.text = e || "")
                    }
                    Button {
                        text: qsTr("Create AstraID")
                        primary: false
                        onClicked: Account.call("signIn", { email: email.text, password: password.text, register: true }, (r, e) => accountError.text = e || "")
                    }
                }
            }
        }

        // ---- PIN --------------------------------------------------------------------
        Column {
            visible: root.current === "pin"
            x: 24; width: parent.width - 48
            spacing: 14
            Title { text: Lock.hasPin ? qsTr("PIN Set") : qsTr("Screen Lock") }
            Subtitle { text: Lock.hasPin ? qsTr("Your phone asks for it when it unlocks.") : qsTr("Choose a PIN of 4 to 6 digits to protect your phone.") }
            Field {
                id: pin
                visible: !Lock.hasPin
                placeholder: qsTr("New PIN")
                secret: true
                hints: Qt.ImhDigitsOnly
                onAccepted: setPin.clicked()
            }
            Text { id: pinError; visible: text !== ""; color: "#FF6B6B"; font.family: Theme.fontFamily; font.pixelSize: 13 }
            Button {
                id: setPin
                visible: !Lock.hasPin
                text: qsTr("Set PIN")
                enabled: /^\d{4,6}$/.test(pin.text)
                onClicked: { root.dismissKeyboard(); Lock.setPin("", pin.text, (ok, error) => { pinError.text = ok ? "" : (error || ""); if (ok) root.next() }) }
            }
        }

        // ---- appearance -------------------------------------------------------------
        Column {
            visible: root.current === "appearance"
            x: 24; width: parent.width - 48
            spacing: 14
            Title { text: qsTr("Appearance") }
            Row {
                spacing: 12
                Repeater {
                    model: [{ id: "light", label: qsTr("Light"), bg: "#F2F2F7", fg: "#0B0B0F" },
                            { id: "dark", label: qsTr("Dark"), bg: "#1C1C1E", fg: "white" },
                            { id: "auto", label: qsTr("Automatic"), bg: "#6E6E73", fg: "white" }]
                    delegate: Column {
                        id: look
                        required property var modelData
                        spacing: 8
                        Rectangle {
                            width: (content.width - 48 - 24) / 3
                            height: width * 1.6
                            radius: 18
                            color: modelData.bg
                            border.width: (Settings.values["theme.mode"] || "auto") === modelData.id ? 3 : 0
                            border.color: Theme.accent
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater { model: 3; Rectangle { width: 46; height: 8; radius: 4; color: look.modelData.fg; opacity: 0.4 } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: Settings.setValue("theme.mode", look.modelData.id) }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: 14; color: "white" }
                    }
                }
            }
            Choice {
                text: qsTr("Always On Display")
                switchable: true
                selected: !!Settings.values["display.aod"]
                onClicked: Settings.setValue("display.aod", !Settings.values["display.aod"])
            }
        }

        // ---- done ---------------------------------------------------------------------
        Column {
            visible: root.current === "done"
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("You're all set"); font.family: Theme.fontFamily; font.pixelSize: 34; font.weight: Font.Bold; color: "white" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Swipe up from the bottom to go home."); font.family: Theme.fontFamily; font.pixelSize: 15; color: Qt.rgba(1, 1, 1, 0.7) }
        }
    }

    // ---- navigation ------------------------------------------------------------------
    // Back: a round frosted button, top left.
    Rectangle {
        visible: root.step > 0 && root.current !== "done"
        x: 18
        y: Theme.statusBarHeight + 8
        width: 40
        height: 40
        radius: 20
        color: Qt.rgba(1, 1, 1, backArea.pressed ? 0.28 : 0.16)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.2)
        Icon { anchors.centerIn: parent; name: "chevron-left"; size: 20; color: "white" }
        MouseArea { id: backArea; anchors.fill: parent; anchors.margins: -6; onClicked: root.back() }
    }
    // Continue: one wide button at the bottom, as the big phone setups have.
    Column {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 38
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 48
        spacing: 12
        Rectangle {
            width: parent.width
            height: 56
            radius: 28
            color: Qt.rgba(1, 1, 1, nextArea.pressed ? 0.8 : 1)
            scale: nextArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            Text {
                anchors.centerIn: parent
                text: root.current === "hello" ? qsTr("Get Started") : root.current === "done" ? qsTr("Start Using astraOS") : qsTr("Continue")
                font.family: Theme.fontFamily
                font.pixelSize: 17
                font.weight: Font.DemiBold
                color: "#0B0B0F"
            }
            MouseArea { id: nextArea; anchors.fill: parent; onClicked: root.current === "done" ? root.finish() : root.next() }
        }
        // The optional steps can wait.
        Item {
            width: parent.width
            height: 24
            Text {
                visible: (root.current === "astraid" && !Account.state.signedIn) || (root.current === "pin" && !Lock.hasPin)
                anchors.centerIn: parent
                text: qsTr("Set Up Later")
                font.family: Theme.fontFamily
                font.pixelSize: 16
                color: Qt.rgba(1, 1, 1, 0.8)
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: root.next() }
            }
        }
    }

    component Title: Text { font.family: Theme.fontFamily; font.pixelSize: 36; font.weight: Font.Bold; color: "white"; width: parent ? parent.width : 300; wrapMode: Text.WordWrap }
    component Subtitle: Text { font.family: Theme.fontFamily; font.pixelSize: 15; color: Qt.rgba(1, 1, 1, 0.7); width: parent ? parent.width : 300; wrapMode: Text.WordWrap }
    component Choice: Rectangle {
        id: choice
        property string text
        property string detail
        property bool selected: false
        property bool switchable: false
        signal clicked()
        width: parent ? parent.width : 300
        height: 58
        radius: 20
        color: Qt.rgba(1, 1, 1, area.pressed ? 0.24 : 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: choice.text; font.family: Theme.fontFamily; font.pixelSize: 16; color: "white" }
        Text { visible: !choice.switchable && choice.detail !== ""; anchors.right: parent.right; anchors.rightMargin: 46; anchors.verticalCenter: parent.verticalCenter; text: choice.detail; font.family: Theme.fontFamily; font.pixelSize: 13; color: Qt.rgba(1, 1, 1, 0.6) }
        Icon { visible: !choice.switchable && choice.selected; anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 20; color: Theme.accent }
        Switch { visible: choice.switchable; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; checked: choice.selected; enabled: false }
        MouseArea { id: area; anchors.fill: parent; onClicked: choice.clicked() }
    }
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder
        property bool secret: false
        property int hints: 0
        signal accepted()
        width: parent ? parent.width : 300
        height: 58
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        function forceActiveFocus() { input.forceActiveFocus() }
        TextInput {
            id: input
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            verticalAlignment: TextInput.AlignVCenter
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            inputMethodHints: field.hints | Qt.ImhNoAutoUppercase
            font.family: Theme.fontFamily
            font.pixelSize: 16
            color: "white"
            onAccepted: field.accepted()
            Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !parent.text; text: field.placeholder; font: parent.font; color: Qt.rgba(1, 1, 1, 0.45) }
        }
    }
}
