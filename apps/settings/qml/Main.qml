// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings. Deep links (launch arguments / intents):
//   { page: "lockscreen" }                 Lock Screen (from the lock screen long press)
//   { page: "appinfo", package: "<pkg>" }  App Info (from the home screen menu)
//   { page: "wifi" } { page: "bluetooth" } { page: "mobile" }   (from Control Center)
//   { page: "controlcenter" }              Cards (Control Center customization)
//   { page: "privacy" } { page: "display" } { page: "about" } { page: "update" }
//   { page: "developer" } { page: "language" } { page: "notifications" }
Rectangle {
    id: app
    color: Theme.background

    readonly property var routes: ({
        lockscreen: "LockScreenPage.qml",
        wifi: "WifiPage.qml",
        connectivity: "WifiPage.qml",
        bluetooth: "BluetoothPage.qml",
        mobile: "MobilePage.qml",
        controlcenter: "CardsPage.qml",
        privacy: "PrivacyPage.qml",
        display: "DisplayPage.qml",
        about: "AboutPage.qml",
        update: "UpdatePage.qml",
        developer: "DeveloperPage.qml",
        language: "LanguagePage.qml",
        notifications: "NotificationsPage.qml",
        battery: "BatteryPage.qml",
        sound: "SoundPage.qml",
        focus: "FocusPage.qml",
        hotspot: "HotspotPage.qml",
        location: "LocationPage.qml",
        account: "AccountPage.qml"
    })

    PageStack {
        id: stack
        anchors.fill: parent
    }

    function route(args) {
        if (!args || !args.page)
            return
        stack.pop(null)
        if (args.page === "appinfo")
            stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: args.package })
        else if (routes[args.page])
            stack.open(Qt.resolvedUrl(routes[args.page]))
    }

    Component.onCompleted: {
        stack.open(Qt.resolvedUrl("HomePage.qml"))
        route(Application.args)
    }
    Connections {
        target: Application
        function onIntent(args) { app.route(args) }
    }
}
