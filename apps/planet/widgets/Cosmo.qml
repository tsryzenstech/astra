// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Lock screen widget (small): Planet / Cosmo shortcut glyph.
Item {
    AppIcon {
        anchors.centerIn: parent
        size: 40
        round: true
        source: Qt.resolvedUrl("../icon.svg")
    }
}
