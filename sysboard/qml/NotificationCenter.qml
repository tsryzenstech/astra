// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Notification Center (NotificationCenter.png). Shows the notifications
// actually received; new ones appear live while it is open. "Clear" only
// exists when there is something to clear.
Item {
    id: root

    property var panel
    property var shell

    PanelEntrance {
        panel: root.panel
        order: 0
        x: 28
        y: 96
        width: 300
        height: 90

        Text {
            id: clock
            text: SystemClock.time
            font.family: Theme.fontFamily
            font.pixelSize: 62
            font.weight: Font.DemiBold
            font.letterSpacing: -1
            color: Qt.rgba(1, 1, 1, 0.92)
        }
        Text {
            anchors.top: clock.bottom
            anchors.topMargin: -14
            text: SystemClock.shortDate
            font.family: Theme.fontFamily
            font.pixelSize: 29
            font.weight: Font.Light
            color: Qt.rgba(1, 1, 1, 0.92)
        }
    }

    Flickable {
        id: list
        x: 27
        y: 200
        width: parent.width - 54
        height: parent.height - y - 40
        contentHeight: column.height + 20
        clip: contentHeight > height
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: parent.width
            spacing: 16

            Repeater {
                model: Notifications
                delegate: PanelEntrance {
                    id: entry
                    required property int index
                    required property int notificationId
                    required property string packageName
                    required property string appName
                    required property url icon
                    required property string title
                    required property string body
                    required property date time

                    panel: root.panel
                    order: Math.min(entry.index + 1, 6)
                    width: column.width
                    height: pill.height

                    NotificationPill {
                        id: pill
                        width: parent.width
                        appName: entry.appName
                        icon: entry.icon
                        title: entry.title
                        body: entry.body
                        time: entry.time
                        onOpenRequested: {
                            Notifications.dismiss(entry.notificationId)
                            root.panel.close()
                            root.shell.launch(entry.packageName, { notification: entry.notificationId }, null)
                        }
                        onDismissRequested: Notifications.dismiss(entry.notificationId)
                    }
                }
            }

            PanelEntrance {
                panel: root.panel
                order: Math.min(Notifications.count + 1, 7)
                width: column.width
                height: 89

                SearchBar {
                    anchors.fill: parent
                    onActivated: (mode) => {
                        root.panel.close()
                        root.shell.launch("com.astra.planet", { mode: mode }, null)
                    }
                }
            }

            Item {
                width: column.width
                height: 24
                visible: Notifications.count > 0

                PanelEntrance {
                    panel: root.panel
                    order: Math.min(Notifications.count + 2, 8)
                    anchors.right: parent.right
                    width: 52
                    height: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(0, 0, 0, 0.62)
                        Text {
                            anchors.centerIn: parent
                            text: qsTr("Clear")
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: Notifications.clear()
                        }
                    }
                }
            }
        }
    }
}
