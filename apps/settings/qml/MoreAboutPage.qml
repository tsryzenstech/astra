// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// About > More Settings: every detail of the software and hardware.
// Tap "Architecture" 7 times to turn on Developer Options; that needs a
// screen lock PIN, which is asked right away.
Page {
    id: page
    title: qsTr("More Settings")

    readonly property var info: System.info
    property int taps: 0
    property string hint: ""
    property bool askingPin: false

    function tapArchitecture() {
        if (Developer.state.enabled) {
            hint = qsTr("Developer Options are already on.")
            return
        }
        taps++
        if (taps >= 7) {
            taps = 0
            if (!Lock.hasPin) {
                Dialogs.show({
                    title: qsTr("Set a PIN first"), icon: "lock",
                    message: qsTr("Developer Options can change how the phone works, so they are protected by your screen lock PIN."),
                    buttons: [ { id: "cancel", label: qsTr("Not now") }, { id: "pin", label: qsTr("Set PIN"), style: "primary" } ]
                }, function(b) { if (b === "pin") stack.open(Qt.resolvedUrl("PinPage.qml")) })
                return
            }
            hint = ""
            askingPin = true
            page.flickable.contentY = 0
        } else if (taps >= 3) {
            hint = qsTr("%n more taps to turn on Developer Options.", "", 7 - taps)
        }
    }
    function enable(pin) {
        Developer.call("setEnabled", { on: true, pin: pin }, function(r, err) {
            if (err) {
                pinEntry.shake()
                return
            }
            page.askingPin = false
            page.hint = qsTr("Developer Options are on. You'll find them under About.")
        })
    }
    function gb(bytes) { return bytes ? (bytes / 1073741824).toFixed(1) + " GB" : "—" }
    function duration(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return (d ? d + "d " : "") + h + "h " + m + "m"
    }

    PinEntry {
        id: pinEntry
        visible: page.askingPin
        title: qsTr("Enter your PIN")
        message: qsTr("to turn on Developer Options")
        length: Lock.pinLength
        onEntered: (pin) => page.enable(pin)
    }
    Button {
        visible: page.askingPin
        anchors.horizontalCenter: parent.horizontalCenter
        primary: false
        text: qsTr("Cancel")
        onClicked: page.askingPin = false
    }

    // Floating toast above the content.
    Rectangle {
        parent: page
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 46
        width: Math.min(parent.width - 40, hintText.implicitWidth + 40)
        height: hintText.implicitHeight + 24
        radius: height / 2
        color: Theme.surfaceRaised
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.08)
        opacity: page.hint !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: hintText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 80)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: page.hint
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize + 1
            font.weight: Font.Medium
            color: Theme.text
        }
    }
    Timer { running: page.hint !== ""; interval: 2600; onTriggered: page.hint = "" }

    ListGroup {
        visible: !page.askingPin
        title: qsTr("Device")
        ListItem {
            text: qsTr("Device name")
            value: page.info.deviceName || "—"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("TextEditPage.qml"), {
                title: qsTr("Device name"), text: page.info.deviceName || "", maximumLength: 40,
                onSave: (t) => System.call("system.setDeviceName", { name: t }, null) })
        }
        ListItem { text: qsTr("Model"); value: page.info.model || "—" }
        ListItem { text: qsTr("Manufacturer"); value: page.info.manufacturer || "—" }
        ListItem { text: qsTr("Codename"); value: page.info.device || "—" }
        ListItem { text: qsTr("Processor"); value: (page.info.cpu || "—") + (page.info.cores ? " • " + qsTr("%n cores", "", page.info.cores) : "") }
        ListItem { text: qsTr("Memory"); value: page.gb(page.info.ram) }
        ListItem { text: qsTr("Storage"); value: page.gb(page.info.storageTotal) }
        ListItem { text: qsTr("Up time"); value: page.info.uptime ? page.duration(page.info.uptime) : "—"; separator: false }
    }

    ListGroup {
        visible: !page.askingPin
        title: qsTr("Software")
        ListItem { text: qsTr("astraOS version"); value: (page.info.version || System.version) + " “" + (page.info.codename || "") + "”" }
        ListItem { text: qsTr("Channel"); value: page.info.channel || "—" }
        ListItem { text: qsTr("Build number"); value: page.info.build || "—" }
        ListItem { text: qsTr("Build ID"); value: page.info.buildId || "—" }
        ListItem { text: qsTr("Build"); value: page.info.display || "—" }
        ListItem { text: qsTr("Build type"); value: page.info.buildType || "—" }
        ListItem { text: qsTr("API level"); value: page.info.apiLevel || "—" }
        ListItem { text: qsTr("Kernel"); value: page.info.kernel || "—" }
        ListItem {
            text: qsTr("Architecture")
            value: page.info.architecture || "—"
            onClicked: page.tapArchitecture()
        }
        ListItem { text: qsTr("Qt"); value: page.info.qt || "—"; separator: false }
    }

    Text {
        visible: !page.askingPin
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: qsTr("astraOS is built on the Linux kernel. It is not based on Android.")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.textTertiary
    }
}
