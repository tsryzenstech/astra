// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

Page {
    id: page

    Item { width: 1; height: 80 }
    Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        name: "settings"
        size: 64
        opacity: 0.35
    }
    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.title + " is coming in a future astraOS update."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.textSecondary
    }
}
