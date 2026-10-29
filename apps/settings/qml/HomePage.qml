// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings home (SettingsHome.png): the concept's groups first, then the
// rest of the system. Developer options appear under About once enabled.
Page {
    id: page
    title: qsTr("Settings")

    readonly property var wifi: Network.state.wifi || {}
    readonly property var bt: Network.state.bluetooth || {}
    readonly property var cell: Network.state.cellular || {}

    function open(file, props) { stack.open(Qt.resolvedUrl(file), props || {}) }

    AccountCard { onClicked: page.open("AccountPage.qml") }

    ListGroup {
        title: qsTr("Connectivity")
        ListItem {
            text: qsTr("Wi-Fi")
            subtitle: page.wifi.state === "connected" ? page.wifi.ssid : ""
            showSwitch: true
            chevron: true
            enabled: page.wifi.available !== false
            checked: !!page.wifi.powered
            onToggled: (on) => Network.call("wifiSetPowered", { on: on }, null)
            onClicked: page.open("WifiPage.qml")
        }
        ListItem {
            text: qsTr("Bluetooth")
            showSwitch: true
            chevron: true
            enabled: page.bt.available !== false
            checked: !!page.bt.powered
            onToggled: (on) => Network.call("btSetPowered", { on: on }, null)
            onClicked: page.open("BluetoothPage.qml")
        }
        ListItem {
            text: qsTr("Cellular Data")
            subtitle: page.cell.simPresent ? (page.cell.operator || "") : (page.cell.available ? qsTr("No SIM card") : "")
            showSwitch: true
            chevron: true
            separator: false
            enabled: !!page.cell.available
            checked: !!page.cell.dataEnabled
            onToggled: (on) => Network.call("cellSetData", { on: on }, null)
            onClicked: page.open("MobilePage.qml")
        }
    }

    ListGroup {
        title: qsTr("Customization")
        ListItem { text: qsTr("General Customization"); chevron: true; onClicked: page.open("GeneralPage.qml") }
        ListItem { text: qsTr("Lock Screen"); chevron: true; onClicked: page.open("LockScreenPage.qml") }
        ListItem { text: qsTr("Privacy Options"); chevron: true; onClicked: page.open("PrivacyPage.qml") }
        ListItem { text: qsTr("Themes"); chevron: true; onClicked: page.open("ThemesPage.qml") }
        ListItem { text: qsTr("Cards"); chevron: true; separator: false; onClicked: page.open("CardsPage.qml") }
    }

    ListGroup {
        title: qsTr("PRISM exclusives")
        ListItem { text: qsTr("Hey Cloudy"); chevron: true; onClicked: page.open("HeyCloudyPage.qml") }
        ListItem { text: qsTr("Store Purchases"); chevron: true; separator: false; onClicked: page.open("PurchasesPage.qml") }
    }

    ListGroup {
        title: qsTr("System")
        ListItem { text: qsTr("Display"); chevron: true; onClicked: page.open("DisplayPage.qml") }
        ListItem { text: qsTr("Sound"); chevron: true; onClicked: page.open("SoundPage.qml") }
        ListItem { text: qsTr("Notifications"); chevron: true; onClicked: page.open("NotificationsPage.qml") }
        ListItem {
            text: qsTr("Battery")
            value: System.batteryLevel >= 0 ? System.batteryLevel + "%" : ""
            chevron: true
            onClicked: page.open("BatteryPage.qml")
        }
        ListItem { text: qsTr("Storage"); chevron: true; onClicked: page.open("StoragePage.qml") }
        ListItem { text: qsTr("Apps"); chevron: true; value: Packages.count; onClicked: page.open("AppsPage.qml") }
        ListItem {
            text: qsTr("Language & Region")
            value: Language.nameOf(Language.current)
            chevron: true
            onClicked: page.open("LanguagePage.qml")
        }
        ListItem { text: qsTr("Date & Time"); chevron: true; onClicked: page.open("DateTimePage.qml") }
        ListItem { text: qsTr("Accessibility"); chevron: true; onClicked: page.open("AccessibilityPage.qml") }
        ListItem {
            text: qsTr("Software Update")
            value: Updates.state.status === "available" || Updates.state.status === "ready" ? qsTr("1 update") : ""
            chevron: true
            onClicked: page.open("UpdatePage.qml")
        }
        ListItem { text: qsTr("Reset"); chevron: true; onClicked: page.open("ResetPage.qml") }
        ListItem {
            text: qsTr("About")
            chevron: true
            separator: Developer.state.enabled === true
            onClicked: page.open("AboutPage.qml")
        }
        ListItem {
            visible: Developer.state.enabled === true
            height: visible ? implicitHeight : 0
            text: qsTr("Developer Options")
            iconName: "code"
            chevron: true
            separator: false
            onClicked: page.open("DeveloperPage.qml")
        }
    }
}
