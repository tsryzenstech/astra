// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings home (SettingsHome.png).
Page {
    id: page
    title: "Settings"

    function comingSoon(title) {
        stack.open(Qt.resolvedUrl("ComingSoonPage.qml"), { title: title })
    }

    AccountCard {}

    ListGroup {
        title: "Connectivity"
        ListItem {
            text: "Wi-Fi"
            showSwitch: true
            checked: System.wifi
            onToggled: (on) => System.setRadio("wifi", on)
        }
        ListItem {
            text: "Bluetooth"
            showSwitch: true
            checked: System.bluetooth
            onToggled: (on) => System.setRadio("bluetooth", on)
        }
        ListItem {
            text: "Cellular Data"
            showSwitch: true
            checked: System.cellular
            separator: false
            onToggled: (on) => System.setRadio("cellular", on)
        }
    }

    ListGroup {
        title: "Customization"
        ListItem { text: "General Customization"; chevron: true; onClicked: page.comingSoon(text) }
        ListItem { text: "Lock Screen"; chevron: true; onClicked: stack.open(Qt.resolvedUrl("LockScreenPage.qml")) }
        ListItem { text: "Privacy Options"; chevron: true; onClicked: page.comingSoon(text) }
        ListItem { text: "Themes"; chevron: true; onClicked: page.comingSoon(text) }
        ListItem { text: "Cards"; chevron: true; separator: false; onClicked: page.comingSoon(text) }
    }

    ListGroup {
        title: "PRISM exclusives"
        ListItem { text: "Hey Cloudy"; chevron: true; onClicked: page.comingSoon(text) }
        ListItem { text: "Store Purchases"; chevron: true; separator: false; onClicked: page.comingSoon(text) }
    }

    ListGroup {
        title: "System"
        ListItem { text: "Display"; chevron: true; onClicked: stack.open(Qt.resolvedUrl("DisplayPage.qml")) }
        ListItem { text: "Apps"; chevron: true; value: Packages.count; onClicked: stack.open(Qt.resolvedUrl("AppsPage.qml")) }
        ListItem { text: "About"; chevron: true; separator: false; onClicked: stack.open(Qt.resolvedUrl("AboutPage.qml")) }
    }

    ListGroup {
        title: "Developer"
        ListItem {
            text: "Testing"
            subtitle: "Notifications, media sessions, AnimationEngine, services"
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("TestingPage.qml"))
        }
    }
}
