// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Home screen widget: one of your recent photos, a new one every hour.
Item {
    id: root
    property string size: "small"
    property var photos: []
    property int pick: 0
    Component.onCompleted: {
        photos = Files.recent(60).filter(f => /\.(jpe?g|png|webp)$/i.test(f.name))
        pick = photos.length ? Math.floor(Math.random() * photos.length) : 0
    }
    Timer { interval: 3600000; repeat: true; running: root.photos.length > 1; onTriggered: root.pick = (root.pick + 1) % root.photos.length }
    Image {
        anchors.fill: parent
        anchors.margins: -14
        visible: root.photos.length > 0
        source: root.photos.length ? "file://" + root.photos[root.pick].path : ""
        sourceSize: Qt.size(600, 600)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    WidgetTile { visible: root.photos.length === 0; anchors.fill: parent; size: root.size; iconName: "image"; accent: "#0A84FF"; title: qsTr("Photos"); subtitle: qsTr("Your memories show up here") }
}
