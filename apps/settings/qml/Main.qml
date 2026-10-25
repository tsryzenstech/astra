// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings. Deep links (launch arguments / intents):
//   { page: "lockscreen" }                 Lock Screen (from the lock screen long press)
//   { page: "appinfo", package: "<pkg>" }  App Info (from the home screen menu)
//   { page: "connectivity" }               Wi-Fi & Bluetooth (from Control Center)
//   { page: "controlcenter" }              Control Center customization
Rectangle {
    id: app
    color: Theme.background

    PageStack {
        id: stack
        anchors.fill: parent
    }

    function route(args) {
        if (!args || !args.page)
            return
        stack.pop(null)
        switch (args.page) {
        case "lockscreen":
            stack.open(Qt.resolvedUrl("LockScreenPage.qml"))
            break
        case "appinfo":
            stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: args.package })
            break
        case "controlcenter":
            stack.open(Qt.resolvedUrl("ComingSoonPage.qml"), { title: "Control Center" })
            break
        }
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
