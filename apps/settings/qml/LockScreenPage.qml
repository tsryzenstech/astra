// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls

// Settings > Lock Screen: a live preview, the clock font (Poppins with a
// weight slider, or any other font installed in /system/fonts) and the
// widgets. The PIN lives in Privacy Options.
Page {
    id: page
    title: qsTr("Lock Screen")

    // Poppins weights offered by the slider (ExtraLight .. ExtraBold).
    readonly property var weights: ["ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]
    readonly property var weightLabels: [qsTr("Extra Light"), qsTr("Light"), qsTr("Regular"), qsTr("Medium"),
                                         qsTr("Semi Bold"), qsTr("Bold"), qsTr("Extra Bold")]
    readonly property var fontWeights: ({
        "ExtraLight": Font.ExtraLight, "Light": Font.Light, "Regular": Font.Normal, "Medium": Font.Medium,
        "SemiBold": Font.DemiBold, "Bold": Font.Bold, "ExtraBold": Font.ExtraBold, "Thin": Font.Thin, "Black": Font.Black
    })
    readonly property string family: Settings.values["lockscreen.clock_font"] || "Poppins"
    readonly property bool poppins: family === "Poppins"
    readonly property string weight: Settings.values["lockscreen.clock_weight"] || "SemiBold"
    readonly property int clockWeight: poppins ? (fontWeights[weight] ?? Font.DemiBold) : Font.Normal

    readonly property var selected: Settings.values["lockscreen.widgets"] || []
    readonly property var available: Packages.widgets
    readonly property int maxUnits: 4

    function widgetInfo(key) {
        for (const w of available)
            if (w.key === key)
                return w
        return null
    }
    function unitsOf(w) { return w && w.size === "wide" ? 2 : 1 }
    readonly property int usedUnits: selected.reduce((n, k) => n + unitsOf(widgetInfo(k)), 0)
    function setWidgets(list) { Settings.setValue("lockscreen.widgets", list) }

    // ---- preview -----------------------------------------------------------
    Item {
        width: parent.width
        height: 392

        Rectangle {
            id: phone
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 390
            radius: 34
            color: "#3a0020"

            Image {
                id: wall
                anchors.fill: parent
                source: Settings.values["display.wallpaper"]
                        ? System.fileUrl(Settings.values["display.wallpaper"])
                        : System.fileUrl(System.property("ro.system.wallpaper", "/system/media/wallpapers/default_wallpaper.png"))
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 400
                visible: false
            }
            Rectangle { id: wallMask; anchors.fill: parent; radius: parent.radius; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                source: wall
                maskEnabled: true
                maskSource: wallMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Icon { anchors.horizontalCenter: parent.horizontalCenter; y: 32; name: "lock"; size: 11; opacity: 0.85 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 46
                text: Qt.locale().toString(new Date(), "HH:mm")
                font.family: page.family
                font.pixelSize: 54
                font.weight: page.clockWeight
                font.letterSpacing: -1
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 118
                text: Qt.locale().toString(new Date(), "ddd, d MMMM")
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: "white"
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 140
                spacing: 4
                Repeater {
                    model: page.selected
                    delegate: Rectangle {
                        required property var modelData
                        readonly property var info: page.widgetInfo(modelData)
                        width: page.unitsOf(info) === 2 ? 54 : 25
                        height: 25
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.35)
                        AppIcon { anchors.centerIn: parent; size: 13; source: parent.info ? parent.info.iconUrl : "" }
                    }
                }
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                width: 56
                height: 3
                radius: 1.5
                color: "white"
            }
        }
        // The rounded frame around the preview.
        Rectangle {
            anchors.fill: phone
            anchors.margins: -5
            radius: phone.radius + 5
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(1, 1, 1, 0.85)
        }
    }

    // ---- clock font ----------------------------------------------------------
    ListGroup {
        title: qsTr("Clock font")
        footer: Fonts.families.length === 0 ? qsTr("Fonts copied to /system/fonts appear here.") : ""

        Item {
            width: parent.width
            height: fontGrid.height + 28
            Grid {
                id: fontGrid
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                columns: Math.max(1, Math.min(fonts.count, Math.floor((parent.width - 28) / 92)))
                spacing: 12
                Repeater {
                    id: fonts
                    model: ["Poppins"].concat(Fonts.families)
                    delegate: Rectangle {
                        required property string modelData
                        readonly property bool current: modelData === page.family
                        width: 80
                        height: 86
                        radius: Theme.radius
                        color: current ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.surfaceRaised
                        border.color: current ? Theme.accent : "transparent"
                        border.width: 2
                        Column {
                            anchors.centerIn: parent
                            spacing: 2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "12"
                                font.family: modelData
                                font.pixelSize: 30
                                font.weight: modelData === "Poppins" ? page.clockWeight : Font.Normal
                                color: Theme.text
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 70
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                color: Theme.textSecondary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Settings.setValue("lockscreen.clock_font", modelData)
                        }
                    }
                }
            }
        }

        // Poppins: pick the weight.
        Item {
            visible: page.poppins
            width: parent.width
            height: visible ? 92 : 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                text: page.weightLabels[Math.max(0, page.weights.indexOf(page.weight))]
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: Theme.text
            }
            Slider {
                x: 20
                y: 30
                width: parent.width - 40
                from: 0
                to: page.weights.length - 1
                stepSize: 1
                value: Math.max(0, page.weights.indexOf(page.weight))
                onMoved: (v) => Settings.setValue("lockscreen.clock_weight", page.weights[Math.round(v)])
            }
            Text {
                x: 20
                y: 66
                text: "Aa"
                font.family: "Poppins"
                font.weight: Font.ExtraLight
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 20
                y: 66
                text: "Aa"
                font.family: "Poppins"
                font.weight: Font.ExtraBold
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
        }
    }

    // ---- widgets ---------------------------------------------------------------
    ListGroup {
        title: qsTr("Widgets • %1/%2 spaces used").arg(page.usedUnits).arg(page.maxUnits)
        ListItem {
            visible: page.selected.length === 0
            text: qsTr("No widgets")
            subtitle: qsTr("Add widgets from the list below")
            enabled: false
            separator: false
        }
        Repeater {
            model: page.selected
            delegate: ListItem {
                required property var modelData
                required property int index
                readonly property var info: page.widgetInfo(modelData)
                text: info ? info.name : modelData
                subtitle: info ? info.appName + " • " + (info.size === "wide" ? qsTr("Wide") : qsTr("Small")) : qsTr("Not installed")
                iconSource: info ? info.iconUrl : ""
                separator: index < page.selected.length - 1
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "chevron-up"
                    color: Theme.surfaceRaised
                    enabled: index > 0
                    onClicked: {
                        const l = page.selected.slice()
                        l.splice(index - 1, 0, l.splice(index, 1)[0])
                        page.setWidgets(l)
                    }
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "minus"
                    color: Theme.danger
                    onClicked: page.setWidgets(page.selected.filter((k, i) => i !== index))
                }
            }
        }
    }

    ListGroup {
        title: qsTr("Available widgets")
        footer: qsTr("Tip: long press the lock screen to come back here. Apps add their own widgets in their app.json.")
        Repeater {
            id: availableRepeater
            model: page.available.filter(w => !page.selected.includes(w.key))
            delegate: ListItem {
                required property var modelData
                required property int index
                readonly property bool fits: page.usedUnits + page.unitsOf(modelData) <= page.maxUnits
                text: modelData.name
                subtitle: modelData.appName + " • " + (modelData.size === "wide" ? qsTr("Wide") : qsTr("Small"))
                iconSource: modelData.iconUrl
                enabled: fits
                separator: index < availableRepeater.count - 1
                onClicked: page.setWidgets(page.selected.concat([modelData.key]))
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconName: "plus"
                    color: Theme.success
                    onClicked: page.setWidgets(page.selected.concat([modelData.key]))
                }
            }
        }
    }
}
