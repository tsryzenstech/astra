// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.VirtualKeyboard

// System on-screen keyboard. Slides in whenever SysBoard or an app
// focuses a text field.
InputPanel {
    id: panel
    width: parent ? parent.width : 0
    y: Qt.inputMethod.visible ? 0 : height
    visible: y < height
    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
}
