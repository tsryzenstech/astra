// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// One widget on the home screen. System widgets (the weather greeting and
// web search) are part of SysBoard; app widgets come from the apps'
// app.json ("widgets" with "home": ["small", "medium", "large"]) and get
// `size` set to the size they were placed at.
Item {
    id: root
    property string widgetKey
    property string size: "small"
    property var shell
    readonly property var info: Packages.count >= 0 && !widgetKey.startsWith("system/") ? (Packages.widget(widgetKey) || {}) : ({})

    // The weather headline, as on the first page.
    Greeting {
        visible: root.widgetKey === "system/greeting"
        x: 18 - 10
        anchors.verticalCenter: parent.verticalCenter
    }

    // Web search bar (Planet)
    Rectangle {
        visible: root.widgetKey === "system/search"
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 44
        radius: 22
        color: Qt.rgba(0, 0, 0, 0.3)
        Text {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Search the web")
            font.family: Theme.fontFamily
            font.pixelSize: 14
            color: Qt.rgba(1, 1, 1, 0.75)
        }
        Image {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30
            source: "icons/system/search-glyph.svg"
            sourceSize: Qt.size(60, 60)
        }
    }

    // App widgets: on a frosted card.
    Rectangle {
        visible: !root.widgetKey.startsWith("system/")
        anchors.fill: parent
        radius: Theme.cardRadius
        color: Qt.rgba(0.08, 0.08, 0.1, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        clip: true
        Loader {
            id: loader
            anchors.fill: parent
            anchors.margins: 14
            source: root.info.qmlUrl || ""
            onLoaded: if (item && item.hasOwnProperty("size")) item.size = Qt.binding(() => root.size)
        }
        Text {
            visible: loader.status === Loader.Error
            anchors.centerIn: parent
            text: root.info.name || ""
            font.family: Theme.fontFamily
            font.pixelSize: 13
            color: "white"
        }
    }
}
