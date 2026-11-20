// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > PetalDrop: who may send you photos and files. PetalDrop has no app: you use it from any Share button.
Page {
    id: page
    title: qsTr("PetalDrop")
    readonly property string mode: Settings.values["petaldrop.receive"] || "mydevices"

    ListGroup {
        title: qsTr("Receiving")
        footer: page.mode === "off" ? qsTr("Nobody can send you anything, and this device does not show up for others.")
              : page.mode === "mydevices" ? qsTr("Only your own phones and computers, signed in to your AstraID, can send you files, with no question asked.")
              : qsTr("Anybody on the same network can ask to send you something. You answer each time.")
        ListItem { text: qsTr("Off"); selected: page.mode === "off"; onClicked: Settings.setValue("petaldrop.receive", "off") }
        ListItem { text: qsTr("My Devices"); selected: page.mode === "mydevices"; onClicked: Settings.setValue("petaldrop.receive", "mydevices") }
        ListItem { text: qsTr("Everyone"); selected: page.mode === "everyone"; separator: false; onClicked: Settings.setValue("petaldrop.receive", "everyone") }
    }
    ListGroup {
        title: qsTr("How to send")
        footer: qsTr("Tap Share in Photos or Files: the devices near you are listed there. Received files go to Download > PetalDrop.")
        ListItem { text: qsTr("Devices nearby"); value: PetalDrop.state.peers ? String(PetalDrop.state.peers.length) : "0"; separator: false }
    }
}
