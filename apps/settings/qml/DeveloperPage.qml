// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Developer Options (turned on from About > More Settings).
// USB debugging lets a computer manage the phone with ADU, the Astra
// Debugging Utility (tools/adu): shell, files, apps, logs, screenshots.
Page {
    id: page
    title: qsTr("Developer Options")

    readonly property var dev: Developer.state
    readonly property var hosts: dev.hosts || []

    ListGroup {
        ListItem {
            text: qsTr("Developer Options")
            showSwitch: true
            checked: !!page.dev.enabled
            separator: false
            onToggled: (on) => {
                if (!on)
                    Developer.call("setEnabled", { on: false }, function() { page.stack.pop() })
            }
        }
    }

    ListGroup {
        title: qsTr("Debugging")
        footer: page.dev.usbDebugging
                ? qsTr("Connect the phone with a USB cable and run “adu shell” on your computer. The phone is at %1, port %2.")
                  .arg(page.dev.usbAddress || "10.42.0.1").arg(page.dev.port || 5560)
                : qsTr("Lets a computer connected over USB run commands, install apps and read logs with ADU.")
        ListItem {
            text: qsTr("USB debugging")
            iconName: "usb"
            showSwitch: true
            checked: !!page.dev.usbDebugging
            onToggled: (on) => Developer.call("setUsbDebugging", { on: on }, null)
        }
        ListItem {
            text: qsTr("Wireless debugging")
            subtitle: qsTr("Also accept ADU over Wi-Fi networks you trust.")
            iconName: "wifi"
            showSwitch: true
            checked: !!page.dev.wireless
            onToggled: (on) => Developer.call("setWireless", { on: on }, null)
        }
        ListItem {
            text: qsTr("Authorized computers")
            value: page.hosts.length
            separator: page.hosts.length > 0
            enabled: false
        }
        Repeater {
            model: page.hosts
            delegate: ListItem {
                required property var modelData
                text: modelData.name || qsTr("Computer")
                subtitle: (modelData.fingerprint || "").substring(0, 16).toUpperCase().replace(/(..)/g, "$1:").slice(0, -1)
                iconName: "devices"
            }
        }
        ListItem {
            visible: page.hosts.length > 0
            text: qsTr("Revoke USB debugging authorizations")
            destructive: true
            separator: false
            onClicked: Developer.call("revokeAuthorizations", {}, null)
        }
    }

    ListGroup {
        title: qsTr("Interface")
        ListItem {
            text: qsTr("Animation speed")
            readonly property real scale: Number(Settings.values["developer.animation_scale"] ?? 1)
            value: scale === 0 ? qsTr("Off") : scale + "×"
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Animation speed"), key: "developer.animation_scale",
                footer: qsTr("Applies to apps opened from now on."),
                options: [ { value: 0, label: qsTr("Off") }, { value: 0.5, label: "0.5×" }, { value: 1, label: "1× " + qsTr("(default)") },
                           { value: 1.5, label: "1.5×" }, { value: 2, label: "2×" }, { value: 5, label: "5×" } ] })
        }
        SwitchRow {
            text: qsTr("Stay awake")
            subtitle: qsTr("The screen never turns off while charging.")
            key: "developer.stay_awake"
            separator: false
        }
    }

    ListGroup {
        title: qsTr("System")
        ListItem {
            text: qsTr("Restart SysBoard")
            subtitle: qsTr("Restarts the system UI and goes back to the lock screen.")
            iconName: "refresh"
            onClicked: System.power("restart-sysboard")
        }
        ListItem {
            text: qsTr("Testing tools")
            subtitle: qsTr("Notifications, media sessions, AnimationEngine, services")
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("TestingPage.qml"))
        }
        ListItem { text: qsTr("Reboot"); onClicked: System.power("reboot") }
        ListItem { text: qsTr("Reboot to bootloader"); destructive: true; separator: false; onClicked: System.power("bootloader") }
    }
}
