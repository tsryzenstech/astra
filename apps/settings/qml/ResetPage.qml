// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Reset: settings back to their defaults, or erase the phone.
Page {
    id: page
    title: qsTr("Reset")

    property string error: ""
    // Keys reset by "Reset all settings" (accounts, PIN and apps stay).
    readonly property var keys: Object.keys(Settings.values).filter(k => !k.startsWith("account.") && !k.startsWith("secure.")
                                                                      && !k.startsWith("app.") && k !== "home.layout"
                                                                      && k !== "system.welcome_posted")

    function eraseAfterPin(pin) {
        Lock.verify(pin, function(ok) {
            if (!ok) {
                pinEntry.shake()
                return
            }
            System.call("system.factoryReset", {}, function(r, err) { page.error = err || "" })
        })
    }

    ListGroup {
        footer: qsTr("Wi-Fi networks, display, sound and every other setting go back to how they were. Your apps and data stay.")
        ListItem {
            text: qsTr("Reset all settings")
            textColor: Theme.accent
            separator: false
            onClicked: Dialogs.show({
                title: qsTr("Reset all settings?"), icon: "reset",
                message: qsTr("Your apps, photos and files are not touched."),
                buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "reset", label: qsTr("Reset"), style: "destructive" } ]
            }, function(b) {
                if (b === "reset")
                    for (const k of page.keys)
                        Settings.reset(k)
            })
        }
    }

    ListGroup {
        footer: qsTr("Erases apps, accounts, photos and everything else on this phone, then restarts it like new.")
        ListItem {
            text: qsTr("Erase all content and settings")
            destructive: true
            separator: false
            onClicked: Dialogs.show({
                title: qsTr("Erase this phone?"), icon: "trash",
                message: qsTr("This can't be undone."),
                buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "erase", label: qsTr("Erase"), style: "destructive" } ]
            }, function(b) {
                if (b !== "erase")
                    return
                if (Lock.hasPin)
                    pinEntry.visible = true
                else
                    System.call("system.factoryReset", {}, function(r, err) { page.error = err || "" })
            })
        }
    }

    PinEntry {
        id: pinEntry
        visible: false
        title: qsTr("Enter your PIN to erase the phone")
        length: Lock.pinLength
        onEntered: (pin) => page.eraseAfterPin(pin)
    }

    Text {
        visible: page.error !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.error
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize + 1
        color: Theme.danger
    }
}
