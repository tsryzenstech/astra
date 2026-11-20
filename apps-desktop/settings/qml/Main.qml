// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Settings for astraOS Desktop: a sidebar of the sections and the section next to it, as on a computer, instead of the
// phone's list that pushes pages. The pages are the phone's (apps/settings/qml, laid over by this file at build time) in a
// column in the middle of the window, and what they open (a choice, a network...) opens in the same column.
//
// Deep links (launch arguments / intents) are the phone's: { page: "display" }, { page: "appinfo", package: "<pkg>" } ...
Rectangle {
    id: app
    color: Theme.background
    focus: true

    // The sections, in the order of the sidebar: the pages exist in apps/settings (the phone's), except Keyboard and Trackpad.
    readonly property var groups: [
        { items: [
            { id: "account", text: qsTr("AstraID"), icon: "person", file: "AccountPage.qml" } ] },
        { items: [
            { id: "wifi", text: qsTr("Wi-Fi"), icon: "wifi", file: "WifiPage.qml" },
            { id: "bluetooth", text: qsTr("Bluetooth"), icon: "bluetooth", file: "BluetoothPage.qml" },
            { id: "petaldrop", text: qsTr("PetalDrop"), icon: "share", file: "PetalDropPage.qml" },
            { id: "phonelinker", text: qsTr("Phone Linker"), icon: "phone", file: "PhoneLinkPage.qml" } ] },
        { items: [
            { id: "display", text: qsTr("Display"), icon: "display", file: "DisplayPage.qml" },
            { id: "sound", text: qsTr("Sound"), icon: "sound", file: "SoundPage.qml" },
            { id: "notifications", text: qsTr("Notifications"), icon: "notification", file: "NotificationsPage.qml" },
            { id: "focus", text: qsTr("Focus"), icon: "moon", file: "FocusPage.qml" },
            { id: "battery", text: qsTr("Battery"), icon: "battery", file: "BatteryPage.qml" } ] },
        { items: [
            { id: "keyboard", text: qsTr("Keyboard"), icon: "keypad", file: "KeyboardPage.qml" },
            { id: "trackpad", text: qsTr("Mouse & Trackpad"), icon: "desktop", file: "TrackpadPage.qml" },
            { id: "desktop", text: qsTr("Desktop"), icon: "grid", file: "DesktopPage.qml" },
            { id: "lockscreen", text: qsTr("Lock Screen"), icon: "lock", file: "LockScreenPage.qml" },
            { id: "themes", text: qsTr("Themes"), icon: "palette", file: "ThemesPage.qml" } ] },
        { items: [
            { id: "language", text: qsTr("Language & Region"), icon: "language", file: "LanguagePage.qml" },
            { id: "datetime", text: qsTr("Date & Time"), icon: "clock", file: "DateTimePage.qml" },
            { id: "accessibility", text: qsTr("Accessibility"), icon: "accessibility", file: "AccessibilityPage.qml" } ] },
        { items: [
            { id: "privacy", text: qsTr("Privacy Options"), icon: "shield", file: "PrivacyPage.qml" },
            { id: "apps", text: qsTr("Apps"), icon: "grid", file: "AppsPage.qml" },
            { id: "storage", text: qsTr("Storage"), icon: "storage", file: "StoragePage.qml" } ] },
        { items: [
            { id: "update", text: qsTr("Software Update"), icon: "refresh", file: "UpdatePage.qml" },
            { id: "about", text: qsTr("About"), icon: "info", file: "AboutPage.qml" } ] }
    ]
    // The phone's names for deep links that point to a page of this list or to another one.
    readonly property var aliases: ({
        connectivity: "wifi", controlcenter: "desktop", lockscreen: "lockscreen", developer: "about"
    })
    readonly property var extraRoutes: ({
        developer: "DeveloperPage.qml", reset: "ResetPage.qml", location: "LocationPage.qml", hotspot: "HotspotPage.qml"
    })

    property string current: "display"
    property string query: ""

    readonly property var flat: {
        const out = []
        for (const g of groups)
            for (const i of g.items)
                out.push(i)
        return out
    }

    function itemFor(id) { return flat.find(i => i.id === id) }

    function show(id) {
        const item = itemFor(id)
        if (!item)
            return
        current = id
        stack.pop(null)
        stack.replace(null, Qt.resolvedUrl(item.file), { stack: stack })
    }

    function route(args) {
        if (!args || !args.page)
            return
        if (args.page === "appinfo") {
            current = "apps"
            stack.pop(null)
            stack.replace(null, Qt.resolvedUrl("AppsPage.qml"), { stack: stack })
            stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: args.package })
        } else if (itemFor(args.page)) {
            show(args.page)
        } else if (aliases[args.page] && itemFor(aliases[args.page])) {
            show(aliases[args.page])
        } else if (extraRoutes[args.page]) {
            stack.pop(null)
            stack.replace(null, Qt.resolvedUrl(extraRoutes[args.page]), { stack: stack })
        }
    }

    // ---- the sidebar --------------------------------------------------------------------------
    Rectangle {
        id: sidebar
        width: 250
        height: parent.height
        color: Theme.light ? Qt.rgba(0, 0, 0, 0.04) : Qt.rgba(1, 1, 1, 0.05)

        TextField {
            id: search
            x: 14; y: 14
            width: parent.width - 28
            height: 38
            radius: 19
            placeholder: qsTr("Search Settings")
            onTextChanged: app.query = text.trim().toLowerCase()
            onAccepted: if (list.count > 0) app.show(list.model[0].id)
        }

        Flickable {
            id: scroller
            y: 66
            width: parent.width
            height: parent.height - y
            contentHeight: column.height + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: column
                width: parent.width
                spacing: 0

                // Searching: one list of what matches.
                Repeater {
                    id: list
                    model: app.query === "" ? [] : app.flat.filter(i => i.text.toLowerCase().indexOf(app.query) >= 0)
                    delegate: Row {
                        required property var modelData
                        required property int index
                        visible: true
                        SidebarItem {
                            x: 10
                            width: column.width - 20
                            text: parent.modelData.text
                            iconName: parent.modelData.icon
                            selected: app.current === parent.modelData.id
                            onClicked: app.show(parent.modelData.id)
                        }
                    }
                }

                Repeater {
                    model: app.query === "" ? app.groups : []
                    delegate: Column {
                        required property var modelData
                        width: column.width
                        Item { width: 1; height: 10 }
                        Repeater {
                            model: parent.modelData.items
                            delegate: SidebarItem {
                                required property var modelData
                                x: 10
                                width: column.width - 20
                                text: modelData.text
                                iconName: modelData.icon
                                selected: app.current === modelData.id
                                onClicked: app.show(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle { x: sidebar.width; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, Theme.light ? 0.0 : 0.08) }

    // ---- the section ----------------------------------------------------------------------------
    Item {
        id: content
        x: sidebar.width + 1
        width: parent.width - x
        height: parent.height

        // The phone's pages are made for a narrow column: they stay in one, in the middle.
        PageStack {
            id: stack
            width: Math.min(640, parent.width)
            height: parent.height
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    Component.onCompleted: {
        show("display")
        route(Application.args)
    }
    Connections {
        target: Application
        function onIntent(args) { app.route(args) }
    }
}
