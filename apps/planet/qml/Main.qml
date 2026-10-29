// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Loads Planet from Browser.qml: when the system lacks Qt WebEngine, the app says so
// instead of failing to open.
Rectangle {
    id: app
    color: Theme.background

    Loader {
        id: loader
        anchors.fill: parent
        source: Qt.resolvedUrl("Browser.qml")
        asynchronous: false
    }
    EmptyState {
        anchors.centerIn: parent
        width: parent.width - 60
        visible: loader.status === Loader.Error
        iconName: "warning"
        title: qsTr("Planet can't start")
        message: qsTr("This version of astraOS is missing %1, which this app needs. Update the system to use it.").arg("Qt WebEngine")
    }
}
