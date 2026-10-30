// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Controls

// Loads Recorder from RecorderApp.qml: when the system lacks Qt Multimedia, the app says so
// instead of failing to open.
Rectangle {
    id: app
    color: Theme.background

    Loader {
        id: loader
        anchors.fill: parent
        source: Qt.resolvedUrl("RecorderApp.qml")
        asynchronous: false
        // Why it failed: the system module missing, or an error in the app itself.
        readonly property string error: status === Loader.Error ? Qt.createComponent(source).errorString().trim() : ""
        onErrorChanged: if (error) console.warn("Recorder:", error)
    }
    EmptyState {
        anchors.centerIn: parent
        width: parent.width - 60
        visible: loader.status === Loader.Error
        iconName: "warning"
        title: qsTr("Recorder can't start")
        message: /module "QtMultimedia" is not installed/.test(loader.error)
                 ? qsTr("This version of astraOS is missing %1, which this app needs. Update the system to use it.").arg("Qt Multimedia")
                 : loader.error
    }
}
