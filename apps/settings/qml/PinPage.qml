// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Set, change or remove the lock screen PIN (4 to 8 digits).
Page {
    id: page
    title: qsTr("Screen lock PIN")

    // steps: "menu" (PIN set), "current", "new", "confirm"
    property string step: Lock.hasPin ? "menu" : "new"
    property string intent: "set"     // "set" or "remove"
    property string current: ""
    property string fresh: ""
    property string message: ""
    property bool failed: false

    readonly property string prompt: {
        switch (step) {
        case "current": return qsTr("Enter your current PIN")
        case "new": return qsTr("Choose a new PIN")
        case "confirm": return qsTr("Enter the new PIN again")
        }
        return ""
    }

    function start(what) {
        intent = what
        message = ""
        step = "current"
    }
    function report(text, bad) {
        message = text
        failed = bad
        if (bad)
            entry.shake()
    }

    function submit(value) {
        entry.clear()
        message = ""
        if (step === "current") {
            current = value
            if (intent === "remove") {
                Lock.setPin(current, "", (ok, error) => {
                    page.report(ok ? qsTr("PIN removed") : qsTr("Wrong PIN"), !ok)
                    page.step = ok ? "new" : "current"
                })
            } else {
                Lock.verify(current, (ok) => {
                    if (ok)
                        page.step = "new"
                    else
                        page.report(qsTr("Wrong PIN"), true)
                })
            }
        } else if (step === "new") {
            fresh = value
            step = "confirm"
        } else if (step === "confirm") {
            if (value !== fresh) {
                report(qsTr("The PINs don't match"), true)
                step = "new"
                return
            }
            Lock.setPin(current, fresh, (ok, error) => {
                if (ok) {
                    page.report(qsTr("PIN saved"), false)
                    page.step = "menu"
                } else {
                    page.report(error, true)
                    page.step = Lock.hasPin ? "current" : "new"
                }
            })
        }
    }

    ListGroup {
        visible: page.step === "menu"
        footer: qsTr("The PIN unlocks the phone and protects Developer Options and the camera on the lock screen.")
        ListItem { text: qsTr("Change PIN"); chevron: true; onClicked: page.start("set") }
        ListItem { text: qsTr("Remove PIN"); destructive: true; separator: false; onClicked: page.start("remove") }
    }

    Text {
        width: parent.width
        visible: page.message !== ""
        horizontalAlignment: Text.AlignHCenter
        text: page.message
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        font.weight: Font.Medium
        color: page.failed ? Theme.danger : Theme.success
    }

    PinEntry {
        id: entry
        visible: page.step !== "menu"
        title: page.prompt
        message: page.step === "new" ? qsTr("4 to 8 digits") : ""
        length: page.step === "current" ? Lock.pinLength : page.step === "confirm" ? page.fresh.length : 0
        onEntered: (pin) => page.submit(pin)
    }
}
