// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Single line text input on a dark rounded field.
Rectangle {
    id: root

    property alias text: input.text
    property string placeholder
    property alias echoMode: input.echoMode
    property alias inputMethodHints: input.inputMethodHints
    property alias maximumLength: input.maximumLength
    property alias validator: input.validator
    signal accepted()

    function focusInput() { input.forceActiveFocus() }

    implicitWidth: 240
    implicitHeight: 48
    radius: 14
    color: Theme.surfaceRaised
    border.width: input.activeFocus ? 1.5 : 0
    border.color: Theme.accent

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.text
        selectionColor: Theme.accent
        onAccepted: root.accepted()
    }

    Text {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        visible: input.text === "" && !input.activeFocus
        text: root.placeholder
        font: input.font
        color: Theme.textTertiary
    }
}
