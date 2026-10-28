// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Control Center (ControlCenter1.png). Long press the media tile, Wi-Fi or
// Bluetooth to expand it into a menu: the tile grows into a card over the
// blurred controls; tap the blur to collapse it.
Item {
    id: root

    property var panel
    property var shell

    readonly property real colLeft: 31
    readonly property real colGap: (width - 2 * colLeft - 4 * 63) / 3
    readonly property var wifi: Network.state.wifi || {}
    readonly property var bt: Network.state.bluetooth || {}

    function toggleSetting(key) {
        Settings.setValue(key, !Settings.values[key])
    }

    // Must match the catalog in Settings > Cards.
    readonly property var defaultTiles: ["location", "sound", "game", "cast", "focus", "scanner", "work", "dnd"]
    readonly property var cell: Network.state.cellular || {}
    readonly property var tileCatalog: ({
        location: { icon: "location", checked: () => !!Settings.values["controls.location"], run: () => root.toggleSetting("controls.location") },
        sound: { icon: "sound", checked: () => Settings.values["controls.sound"] !== false,
                 run: () => Settings.setValue("controls.sound", Settings.values["controls.sound"] === false) },
        game: { icon: "gamepad", checked: () => !!Settings.values["controls.game"], run: () => root.toggleSetting("controls.game") },
        cast: { icon: "cast", checked: () => !!Settings.values["controls.cast"], run: () => root.toggleSetting("controls.cast") },
        focus: { icon: "focus", checked: () => !!Settings.values["controls.focus"], run: () => root.toggleSetting("controls.focus") },
        scanner: { icon: "qr", checked: () => false, run: () => root.openApp("com.astra.camera", { mode: "scan" }) },
        work: { icon: "briefcase", checked: () => !!Settings.values["controls.work"], run: () => root.toggleSetting("controls.work") },
        dnd: { icon: "moon", checked: () => !!Settings.values["controls.dnd"], run: () => root.toggleSetting("controls.dnd") },
        airplane: { icon: "airplane", checked: () => !!Network.state.airplane,
                    run: () => Network.call("setAirplane", { on: !Network.state.airplane }, null) },
        torch: { icon: "flashlight", checked: () => System.torch, run: () => System.setTorch(!System.torch) },
        nightlight: { icon: "night", checked: () => !!Settings.values["display.night_light"], run: () => root.toggleSetting("display.night_light") },
        data: { icon: "signal", checked: () => !!root.cell.dataEnabled,
                run: () => Network.call("cellSetData", { on: !root.cell.dataEnabled }, null) },
        screenshot: { icon: "image", checked: () => false, run: () => { root.panel.close(); shotTimer.start() } }
    })
    Timer { id: shotTimer; interval: 700; onTriggered: System.screenshot() }
    function openApp(pkg, args) {
        panel.close()
        shell.launch(pkg, args || {}, null)
    }

    // ---- expansion -----------------------------------------------------
    property string expanded: ""        // "", "media", "wifi", "bluetooth"
    property rect expandFrom: Qt.rect(0, 0, 0, 0)
    property real expandFromRadius: 30
    readonly property real expansion: expandSpring.value
    Spring { id: expandSpring; to: 0; response: 0.46; dampingFraction: 0.78 }

    function expand(kind, item, radius) {
        expandFrom = item.mapToItem(root, 0, 0, item.width, item.height)
        expandFromRadius = radius
        expanded = kind
        expandSpring.animateTo(1, 0)
    }
    function collapse() {
        expandSpring.animateTo(0, 0)
    }
    Connections {
        target: expandSpring
        function onSettled() { if (expandSpring.value < 0.01) root.expanded = "" }
    }
    Connections {
        target: root.panel
        function onOpenedChanged() { if (!root.panel.opened) { expandSpring.snap(0); root.expanded = "" } }
    }

    Item {
        id: controls
        anchors.fill: parent
        opacity: 1 - 0.25 * root.expansion

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
                id: mediaTile
                anchors.fill: parent
                opacity: root.expanded === "media" ? 0 : 1
                onOpenRequested: (pkg) => root.openApp(pkg || "com.astra.tune")
                onExpandRequested: root.expand("media", mediaTile, mediaTile.radius)
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
                id: wifiPill
                anchors.fill: parent
                opacity: root.expanded === "wifi" ? 0 : 1
                iconName: "wifi"
                text: qsTr("Wi-Fi")
                subtitle: !root.wifi.powered ? qsTr("Off") : root.wifi.state === "connected" ? (root.wifi.ssid || "")
                          : root.wifi.state === "connecting" ? qsTr("Connecting…") : qsTr("Not connected")
                checked: !!root.wifi.powered
                onToggled: Network.call("wifiSetPowered", { on: !root.wifi.powered }, null)
                onDetails: root.expand("wifi", wifiPill, wifiPill.radius)
                onPressAndHold: root.expand("wifi", wifiPill, wifiPill.radius)
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
                id: btPill
                anchors.fill: parent
                opacity: root.expanded === "bluetooth" ? 0 : 1
                iconName: "bluetooth"
                text: qsTr("Bluetooth")
                subtitle: {
                    if (!root.bt.powered)
                        return qsTr("Off")
                    const connected = (root.bt.devices || []).filter(d => d.connected)
                    return connected.length === 1 ? connected[0].name
                         : connected.length > 1 ? qsTr("%n devices", "", connected.length) : qsTr("On")
                }
                checked: !!root.bt.powered
                onToggled: Network.call("btSetPowered", { on: !root.bt.powered }, null)
                onDetails: root.expand("bluetooth", btPill, btPill.radius)
                onPressAndHold: root.expand("bluetooth", btPill, btPill.radius)
            }
        }

        // Toggle grid: eight controls chosen in Settings > Cards.
        Repeater {
            model: (Settings.values["controls.tiles"] || root.defaultTiles).slice(0, 8)
                   .map(id => root.tileCatalog[id]).filter(t => !!t)
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
                    checked: modelData.checked()
                    onClicked: modelData.run()
                }
            }
        }
    }

    // ---- expanded menu ---------------------------------------------------
    BlurLayer {
        anchors.fill: parent
        source: controls
        amount: root.expansion
        dim: 0.25
        hideSource: true
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.expanded !== ""
        onClicked: root.collapse()
    }

    Rectangle {
        id: card
        visible: root.expanded !== ""
        readonly property rect target: Qt.rect(20, 104, root.width - 40,
                                               root.expanded === "media" ? 430 : Math.min(root.height - 190, 520))
        readonly property real t: Math.max(0, root.expansion)
        function lerp(a, b) { return a + (b - a) * t }
        x: lerp(root.expandFrom.x, target.x)
        y: lerp(root.expandFrom.y, target.y)
        width: Math.max(1, lerp(root.expandFrom.width, target.width))
        height: Math.max(1, lerp(root.expandFrom.height, target.height))
        radius: Math.min(height / 2, lerp(root.expandFromRadius, Theme.sheetRadius))
        color: Qt.rgba(0.07, 0.07, 0.08, 0.92)
        clip: true

        MouseArea { anchors.fill: parent } // taps inside do not collapse

        Loader {
            id: menu
            width: card.target.width
            height: card.target.height
            // Content keeps its final size and fades in once there is room.
            scale: Math.min(1, card.width / card.target.width)
            transformOrigin: Item.TopLeft
            opacity: Math.max(0, (root.expansion - 0.45) / 0.55)
            active: root.expanded !== ""
            sourceComponent: root.expanded === "wifi" ? wifiMenu : root.expanded === "bluetooth" ? btMenu : mediaMenu
        }
    }

    Component {
        id: wifiMenu
        WifiMenu { onSettingsRequested: root.openApp("com.astra.settings", { page: "wifi" }) }
    }
    Component {
        id: btMenu
        BluetoothMenu { onSettingsRequested: root.openApp("com.astra.settings", { page: "bluetooth" }) }
    }
    Component {
        id: mediaMenu
        MediaMenu { onOpenRequested: (pkg) => root.openApp(pkg || "com.astra.tune") }
    }
}
