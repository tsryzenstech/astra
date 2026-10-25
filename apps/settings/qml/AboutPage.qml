// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    id: page
    title: "About"

    readonly property var info: System.info

    Image {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 180
        height: 51
        source: System.fileUrl("/system/media/brand/astra_white.svg")
        sourceSize: Qt.size(360, 102)
        fillMode: Image.PreserveAspectFit
    }

    ListGroup {
        ListItem { text: "Version"; value: (page.info.version || System.version) }
        ListItem { text: "Release"; value: page.info.release || "—" }
        ListItem { text: "Build"; value: page.info.buildType || "—" }
        ListItem { text: "API level"; value: page.info.apiLevel || "—"; separator: false }
    }

    ListGroup {
        title: "Device"
        ListItem { text: "Model"; value: page.info.model || "—" }
        ListItem { text: "Codename"; value: page.info.device || "—" }
        ListItem { text: "Kernel"; value: page.info.kernel || "—" }
        ListItem { text: "Architecture"; value: page.info.architecture || "—" }
        ListItem { text: "Qt"; value: page.info.qt || "—"; separator: false }
    }

    Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "astraOS is built on the Linux kernel. It is not based on Android."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.textTertiary
    }
}
