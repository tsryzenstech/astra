// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Edits one line of text; onSave(text) is called with the trimmed value.
Page {
    id: page
    property string text
    property int maximumLength: 64
    property string placeholder
    property var onSave: null

    TextField {
        id: field
        width: parent.width
        text: page.text
        placeholder: page.placeholder
        maximumLength: page.maximumLength
        onAccepted: save.clicked()
        Component.onCompleted: focusInput()
    }
    Button {
        id: save
        width: parent.width
        text: qsTr("Save")
        enabled: field.text.trim().length > 0
        onClicked: {
            if (page.onSave)
                page.onSave(field.text.trim())
            page.stack.pop()
        }
    }
}
