// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Control Center (ControlCenter1.png).
Item {
    id: root

    property var panel
    property var shell

    readonly property real colLeft: 31
    readonly property real colGap: (width - 2 * colLeft - 4 * 63) / 3

    function toggleSetting(key) {
        Settings.setValue(key, !Settings.values[key])
    }
    function openApp(pkg, args) {
        panel.close()
        shell.launch(pkg, args || {}, null)
    }

    // Top row: Settings and edit
    PanelEntrance {
        panel: root.panel
        order: 0
        x: 31
        y: 100
        width: 50
        height: 50
        RoundButton { anchors.fill: parent; iconName: "settings"; onClicked: root.openApp("com.astra.settings") }
    }
    PanelEntrance {
        panel: root.panel
        order: 0
        x: root.width - 31 - 50
        y: 100
        width: 50
        height: 50
        RoundButton { anchors.fill: parent; iconName: "edit"; onClicked: root.openApp("com.astra.settings", { page: "controlcenter" }) }
    }

    // Media + sliders
    PanelEntrance {
        panel: root.panel
        order: 1
        x: 31
        y: 169
        width: 152
        height: 152
        MediaTile {
            anchors.fill: parent
            onOpenRequested: (pkg) => root.openApp(pkg || "com.astra.tune")
        }
    }
    PanelEntrance {
        panel: root.panel
        order: 1
        x: 208
        y: 169
        width: 66
        height: 152
        VerticalSlider {
            anchors.fill: parent
            iconName: "brightness"
            value: System.brightness
            onMoved: (v) => System.setBrightness(Math.max(0.02, v))
        }
    }
    PanelEntrance {
        panel: root.panel
        order: 1
        x: root.width - 31 - 66
        y: 169
        width: 66
        height: 152
        VerticalSlider {
            anchors.fill: parent
            iconName: "volume"
            value: Settings.values["audio.volume"] ?? 0.6
            onMoved: (v) => Settings.setValue("audio.volume", v)
        }
    }

    // Connectivity pills
    PanelEntrance {
        panel: root.panel
        order: 2
        x: 31
        y: 341
        width: 152
        height: 67
        RadioPill {
            anchors.fill: parent
            iconName: "wifi"
            text: "Wi-Fi"
            checked: System.wifi
            onToggled: System.setRadio("wifi", !System.wifi)
            onDetails: root.openApp("com.astra.settings", { page: "connectivity" })
        }
    }
    PanelEntrance {
        panel: root.panel
        order: 2
        x: root.width - 31 - 153
        y: 341
        width: 153
        height: 67
        RadioPill {
            anchors.fill: parent
            iconName: "bluetooth"
            text: "Bluetooth"
            checked: System.bluetooth
            onToggled: System.setRadio("bluetooth", !System.bluetooth)
            onDetails: root.openApp("com.astra.settings", { page: "connectivity" })
        }
    }

    // Toggle grid
    Repeater {
        model: [
            { icon: "location", key: "controls.location" },
            { icon: "sound", key: "controls.sound" },
            { icon: "gamepad", key: "controls.game" },
            { icon: "cast", key: "controls.cast" },
            { icon: "focus", key: "controls.focus" },
            { icon: "qr", action: "scan" },
            { icon: "briefcase", key: "controls.work" },
            { icon: "moon", key: "controls.dnd" }
        ]
        delegate: PanelEntrance {
            required property var modelData
            required property int index
            panel: root.panel
            order: 3 + Math.floor(index / 4)
            x: root.colLeft + (index % 4) * (63 + root.colGap)
            y: 427 + Math.floor(index / 4) * 87
            width: 63
            height: 63
            ControlToggle {
                anchors.fill: parent
                iconName: modelData.icon
                checked: modelData.key ? !!Settings.values[modelData.key] : false
                onClicked: {
                    if (modelData.key)
                        root.toggleSetting(modelData.key)
                    else
                        root.openApp("com.astra.camera", { mode: "scan" })
                }
            }
        }
    }
}
