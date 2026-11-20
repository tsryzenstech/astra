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

    // NFC is listed when the phone has it: astrad's nfc service says.
    property var nfc: ({})
    function refreshNfc() { System.call("nfc.state", {}, function(r, err) { if (!err && r) page.nfc = r }) }
    Component.onCompleted: refreshNfc()
    onVisibleChanged: if (visible) refreshNfc()

    function open(file, props) { stack.open(Qt.resolvedUrl(file), props || {}) }

    // ---- search: a bar above the title, there when the page is pulled all the way down ----------
    readonly property real searchSpace: Theme.statusBarHeight + 54
    property bool searchOpen: false
    property string query: ""
    readonly property var searchIndex: [
        { text: qsTr("Wi-Fi"), words: "wifi wi-fi network internet rete", file: "WifiPage.qml", icon: "wifi" },
        { text: qsTr("Bluetooth"), words: "bluetooth headphones cuffie", file: "BluetoothPage.qml", icon: "bluetooth" },
        { text: qsTr("Cellular Data"), words: "mobile cellular sim data dati", file: "MobilePage.qml", icon: "signal" },
        { text: qsTr("Personal Hotspot"), words: "hotspot tethering condividi", file: "HotspotPage.qml", icon: "hotspot" },
        { text: qsTr("NFC"), words: "nfc tag", file: "NfcPage.qml", icon: "nfc" },
        { text: qsTr("Display"), words: "display brightness luminosita night light dark mode scuro aod always on refresh", file: "DisplayPage.qml", icon: "display" },
        { text: qsTr("Sound"), words: "sound volume ringtone suoneria audio vibration", file: "SoundPage.qml", icon: "sound" },
        { text: qsTr("Notifications"), words: "notifications notifiche banners", file: "NotificationsPage.qml", icon: "notification" },
        { text: qsTr("Focus"), words: "focus do not disturb non disturbare game", file: "FocusPage.qml", icon: "moon" },
        { text: qsTr("Battery"), words: "battery batteria charging saver", file: "BatteryPage.qml", icon: "battery" },
        { text: qsTr("Storage"), words: "storage memoria spazio files", file: "StoragePage.qml", icon: "storage" },
        { text: qsTr("Apps"), words: "apps applicazioni permissions permessi", file: "AppsPage.qml", icon: "grid" },
        { text: qsTr("Language & Region"), words: "language lingua region temperature units", file: "LanguagePage.qml", icon: "language" },
        { text: qsTr("Date & Time"), words: "date time ora data timezone fuso", file: "DateTimePage.qml", icon: "clock" },
        { text: qsTr("Accessibility"), words: "accessibility text size motion accessibilita", file: "AccessibilityPage.qml", icon: "accessibility" },
        { text: qsTr("Software Update"), words: "update aggiornamento software ota", file: "UpdatePage.qml", icon: "refresh" },
        { text: qsTr("Reset"), words: "reset erase factory ripristino cancella", file: "ResetPage.qml", icon: "reset" },
        { text: qsTr("About"), words: "about info version device build", file: "AboutPage.qml", icon: "info" },
        { text: qsTr("Lock Screen"), words: "lock screen schermata blocco wallpaper sfondo clock font", file: "LockScreenPage.qml", icon: "lock" },
        { text: qsTr("Privacy Options"), words: "privacy pin passcode location permissions", file: "PrivacyPage.qml", icon: "shield" },
        { text: qsTr("Location Services"), words: "location gps posizione", file: "LocationPage.qml", icon: "location" },
        { text: qsTr("Themes"), words: "themes temi accent colour wallpaper", file: "ThemesPage.qml", icon: "palette" },
        { text: qsTr("Cards"), words: "cards control center controlli", file: "CardsPage.qml", icon: "sliders" },
        { text: qsTr("General Customization"), words: "general customization home layout icons", file: "GeneralPage.qml", icon: "settings" },
        { text: qsTr("Cloudy"), words: "cloudy assistant ai", file: "HeyCloudyPage.qml", icon: "sparkles" },
        { text: qsTr("Store Purchases"), words: "store purchases acquisti market", file: "PurchasesPage.qml", icon: "bag" },
        { text: qsTr("AstraID"), words: "astraid account login accedi", file: "AccountPage.qml", icon: "person" },
        { text: qsTr("Phone Linker"), words: "phone linker link computer desktop collega telefono contacts photos notifications", file: "PhoneLinkPage.qml", icon: "phone" },
        { text: qsTr("PetalDrop"), words: "petaldrop airdrop share send nearby condividi invia", file: "PetalDropPage.qml", icon: "share" }
    ]
    readonly property var found: {
        const q = page.query.trim().toLowerCase()
        if (!q)
            return []
        return searchIndex.filter(e => (e.text + " " + e.words).toLowerCase().indexOf(q) >= 0)
    }
    onSearchOpenChanged: {
        page.flickable.topMargin = searchOpen ? searchSpace : 0
        Qt.callLater(function() { page.flickable.returnToBounds() })
        if (!searchOpen)
            page.query = ""
    }
    Connections {
        target: page.flickable
        function onContentYChanged() {
            const f = page.flickable
            if (!page.searchOpen && f.dragging && f.contentY < -70)
                page.searchOpen = true
            else if (page.searchOpen && page.query === "" && !searchField.activeFocus && !f.dragging && f.contentY > 24)
                page.searchOpen = false
        }
    }
    TextField {
        id: searchField
        parent: page.flickable.contentItem
        x: Theme.margin
        y: -page.searchSpace + Theme.statusBarHeight + 4
        width: page.width - 2 * Theme.margin
        height: 44
        radius: 22
        placeholder: qsTr("Search Settings")
        visible: page.searchOpen
        onTextChanged: page.query = text
    }

    ListGroup {
        visible: page.query.trim() !== ""
        title: page.found.length ? qsTr("Results") : ""
        footer: page.found.length ? "" : qsTr("No settings match.")
        Repeater {
            model: page.found
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.text
                iconName: modelData.icon
                chevron: true
                separator: index < page.found.length - 1
                onClicked: page.open(modelData.file)
            }
        }
    }

    AccountCard { visible: page.query.trim() === ""; onClicked: page.open("AccountPage.qml") }

    ListGroup {
        visible: page.query.trim() === ""
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
            separator: !!(Network.state.hotspot || {}).supported || page.nfc.available === true
            enabled: !!page.cell.available
            checked: !!page.cell.dataEnabled
            onToggled: (on) => Network.call("cellSetData", { on: on }, null)
            onClicked: page.open("MobilePage.qml")
        }
        ListItem {
            visible: !!(Network.state.hotspot || {}).supported
            text: qsTr("Personal Hotspot")
            value: (Network.state.hotspot || {}).active ? qsTr("On") : qsTr("Off")
            chevron: true
            separator: page.nfc.available === true
            height: visible ? implicitHeight : 0
            onClicked: page.open("HotspotPage.qml")
        }
        ListItem {
            visible: page.nfc.available === true
            height: visible ? implicitHeight : 0
            text: qsTr("NFC")
            showSwitch: true
            chevron: true
            separator: false
            checked: Settings.values["controls.nfc"] === true
            onToggled: (on) => Settings.setValue("controls.nfc", on)
            onClicked: page.open("NfcPage.qml")
        }
    }

    ListGroup {
        visible: page.query.trim() === ""
        title: qsTr("Customization")
        ListItem { text: qsTr("General Customization"); chevron: true; onClicked: page.open("GeneralPage.qml") }
        ListItem { text: qsTr("Lock Screen"); chevron: true; onClicked: page.open("LockScreenPage.qml") }
        ListItem { text: qsTr("Privacy Options"); chevron: true; onClicked: page.open("PrivacyPage.qml") }
        ListItem { text: qsTr("Themes"); chevron: true; onClicked: page.open("ThemesPage.qml") }
        ListItem { text: qsTr("Cards"); chevron: true; separator: false; onClicked: page.open("CardsPage.qml") }
    }

    ListGroup {
        visible: page.query.trim() === ""
        title: qsTr("Devices")
        ListItem {
            visible: System.property("ro.astra.form", "phone") === "desktop"
            height: visible ? implicitHeight : 0
            text: qsTr("Desktop")
            chevron: true
            onClicked: page.open("DesktopPage.qml")
        }
        ListItem { text: qsTr("Phone Linker"); chevron: true; onClicked: page.open("PhoneLinkPage.qml") }
        ListItem { text: qsTr("PetalDrop"); chevron: true; separator: false; onClicked: page.open("PetalDropPage.qml") }
    }

    ListGroup {
        visible: page.query.trim() === ""
        title: qsTr("PRISM exclusives")
        ListItem { text: qsTr("Cloudy"); chevron: true; onClicked: page.open("HeyCloudyPage.qml") }
        ListItem { text: qsTr("Store Purchases"); chevron: true; separator: false; onClicked: page.open("PurchasesPage.qml") }
    }

    ListGroup {
        visible: page.query.trim() === ""
        title: qsTr("System")
        ListItem { text: qsTr("Display"); chevron: true; onClicked: page.open("DisplayPage.qml") }
        ListItem { text: qsTr("Sound"); chevron: true; onClicked: page.open("SoundPage.qml") }
        ListItem { text: qsTr("Notifications"); chevron: true; onClicked: page.open("NotificationsPage.qml") }
        ListItem { text: qsTr("Focus"); chevron: true; value: Settings.values["focus.mode"] ? qsTr("On") : ""; onClicked: page.open("FocusPage.qml") }
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
