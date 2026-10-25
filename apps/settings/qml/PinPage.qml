// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Set, change or remove the lock screen PIN (4 to 8 digits).
Page {
    id: page
    title: "PIN"

    // steps: "menu" (PIN set), "current", "new", "confirm"
    property string step: Lock.hasPin ? "menu" : "new"
    property string intent: "set"     // "set" or "remove"
    property string current: ""
    property string fresh: ""
    property string message: ""

    readonly property string prompt: {
        switch (step) {
        case "current": return "Enter your current PIN"
        case "new": return "Choose a new PIN"
        case "confirm": return "Enter the new PIN again"
        }
        return ""
    }

    function start(what) {
        intent = what
        message = ""
        step = "current"
    }

    function submit(value) {
        keypad.clear()
        message = ""
        if (step === "current") {
            current = value
            if (intent === "remove") {
                Lock.setPin(current, "", (ok, error) => {
                    message = ok ? "PIN removed" : error
                    step = ok ? "new" : "current"
                })
            } else {
                step = "new"
            }
        } else if (step === "new") {
            fresh = value
            step = "confirm"
        } else if (step === "confirm") {
            if (value !== fresh) {
                message = "The PINs don't match"
                step = "new"
                return
            }
            Lock.setPin(current, fresh, (ok, error) => {
                if (ok) {
                    message = "PIN saved"
                    step = "menu"
                } else {
                    message = error
                    step = Lock.hasPin ? "current" : "new"
                }
            })
        }
    }

    ListGroup {
        visible: page.step === "menu"
        ListItem { text: "Change PIN"; chevron: true; onClicked: page.start("set") }
        ListItem { text: "Remove PIN"; destructive: true; separator: false; onClicked: page.start("remove") }
    }

    Text {
        width: parent.width
        visible: page.message !== ""
        horizontalAlignment: Text.AlignHCenter
        text: page.message
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.accent
    }

    Text {
        visible: page.step !== "menu"
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: page.prompt
        font.family: Theme.fontFamily
        font.pixelSize: 19
        font.weight: Font.Medium
        color: Theme.text
    }

    PinKeypad {
        id: keypad
        visible: page.step !== "menu"
        anchors.horizontalCenter: parent.horizontalCenter
        onSubmitted: (value) => page.submit(value)
    }
}
