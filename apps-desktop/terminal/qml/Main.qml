// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// Terminal for astraOS Desktop: a shell, as the user, in a window (astrad's terminal service, a VT100/xterm emulator in
// Astra.Desktop). Ctrl+Shift+C / V copy and paste (what is selected is copied at once), Ctrl+ plus / minus the size of
// the text, Shift+Page Up / Down and the wheel the history.
Rectangle {
    id: app
    color: Theme.surface

    TerminalView {
        id: term
        anchors.fill: parent
        anchors.margins: 12
        anchors.topMargin: 6
        fontSize: Math.round(14 * Theme.fontScale)
        foreground: Theme.text
        background: Theme.surface
        accent: Theme.accent
        focus: true
        property bool autostart: true
        Component.onCompleted: { forceActiveFocus(); start() }
        onExited: Application.quit()
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (point) => {
                const p = term.mapToItem(app, point.position.x, point.position.y)
                menu.popup(p.x, p.y, [
                    { id: "copy", label: qsTr("Copy"), icon: "copy" },
                    { id: "paste", label: qsTr("Paste") },
                    { separator: true },
                    { id: "bigger", label: qsTr("Bigger"), icon: "zoom-in" },
                    { id: "smaller", label: qsTr("Smaller") } ])
            }
        }
    }
    ContextMenu {
        id: menu
        anchors.fill: parent
        onTriggered: (id) => {
            if (id === "copy") term.copy()
            else if (id === "paste") term.paste()
            else if (id === "bigger") term.zoom(1)
            else if (id === "smaller") term.zoom(-1)
            term.forceActiveFocus()
        }
    }
}
