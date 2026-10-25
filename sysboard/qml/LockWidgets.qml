// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Widgets row under the date. Any app can contribute widgets by declaring
// them in app.json ("widgets"); the user picks them in Settings > Lock
// Screen. Sizes: "small" (1 unit) and "wide" (2 units), up to 4 units.
Row {
    id: root

    readonly property real unit: 53
    readonly property var keys: Settings.values["lockscreen.widgets"] || []

    spacing: 9.5

    Repeater {
        model: root.keys

        delegate: Item {
            id: slot
            required property var modelData
            // Re-resolved whenever packages change (install, uninstall, update).
            readonly property var info: Packages.count >= 0 ? Packages.widget(modelData) : ({})
            readonly property bool wide: info.size === "wide"

            visible: info.qmlUrl !== undefined
            width: wide ? root.unit * 2 + root.spacing : root.unit
            height: root.unit

            Rectangle {
                anchors.fill: parent
                radius: 13
                color: Qt.rgba(0, 0, 0, 0.36)
            }

            Loader {
                anchors.fill: parent
                anchors.margins: 6
                source: slot.info.qmlUrl || ""
            }
        }
    }
}
