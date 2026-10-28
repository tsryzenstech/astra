// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    id: page
    property var network: ({})
    property var onJoin: null
    title: network.ssid || ""

    EmptyState {
        iconName: "wifi-lock"
        title: qsTr("Enter the password")
        message: qsTr("“%1” is protected with WPA.").arg(page.network.ssid || "")
    }

    TextField {
        id: field
        width: parent.width
        placeholder: qsTr("Password")
        echoMode: show.checked ? TextInput.Normal : TextInput.Password
        onAccepted: join.clicked()
        Component.onCompleted: focusInput()
    }

    ListGroup {
        ListItem {
            id: show
            text: qsTr("Show password")
            showSwitch: true
            separator: false
            onToggled: (on) => checked = on
        }
    }

    Button {
        id: join
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        text: qsTr("Join")
        enabled: field.text.length >= 8
        onClicked: {
            if (page.onJoin)
                page.onJoin(field.text)
            page.stack.pop()
        }
    }
}
