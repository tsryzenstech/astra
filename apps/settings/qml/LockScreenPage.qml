// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Lock Screen: clock font, widgets, PIN.
Page {
    id: page
    title: "Lock Screen"

    readonly property var weights: ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"]
    readonly property var fontWeights: ({
        "Thin": Font.Thin, "ExtraLight": Font.ExtraLight, "Light": Font.Light, "Regular": Font.Normal,
        "Medium": Font.Medium, "SemiBold": Font.DemiBold, "Bold": Font.Bold, "ExtraBold": Font.ExtraBold, "Black": Font.Black
    })
    readonly property string weight: Settings.values["lockscreen.clock_weight"] || "SemiBold"
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

    // Preview
    Rectangle {
        width: parent.width
        height: 230
        radius: 26
        clip: true
        color: "#3a0020"
        Image {
            anchors.fill: parent
            source: System.fileUrl(System.property("ro.system.wallpaper", "/system/media/wallpapers/default_wallpaper.png"))
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 600
        }
        Column {
            anchors.centerIn: parent
            spacing: -6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(new Date(), "HH:mm")
                font.family: Theme.fontFamily
                font.pixelSize: 84
                font.weight: page.fontWeights[page.weight]
                font.letterSpacing: -2
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDate(new Date(), "ddd, d MMMM")
                font.family: Theme.fontFamily
                font.pixelSize: 17
                color: "white"
            }
        }
    }

    ListGroup {
        title: "Clock font"
        Flow {
            width: parent.width
            padding: 14
            spacing: 10
            Repeater {
                model: page.weights
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool current: modelData === page.weight
                    width: 70
                    height: 70
                    radius: 18
                    color: current ? Qt.rgba(1, 0.48, 0, 0.18) : Theme.surfaceRaised
                    border.color: current ? Theme.accent : "transparent"
                    border.width: 2
                    Column {
                        anchors.centerIn: parent
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "12"
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                            font.weight: page.fontWeights[modelData]
                            color: "white"
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Theme.textSecondary
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Settings.setValue("lockscreen.clock_weight", modelData)
                    }
                }
            }
        }
    }

    ListGroup {
        title: "Widgets  •  " + page.usedUnits + "/" + page.maxUnits + " spaces used"
        ListItem {
            visible: page.selected.length === 0
            text: "No widgets"
            subtitle: "Add widgets from the list below"
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
                subtitle: info ? info.appName + " • " + (info.size === "wide" ? "Wide" : "Small") : "Not installed"
                iconSource: info ? info.iconUrl : ""
                separator: index < page.selected.length - 1
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16
                    Icon {
                        name: "chevron-left"
                        size: 20
                        rotation: 90
                        opacity: index > 0 ? 1 : 0.25
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            enabled: index > 0
                            onClicked: {
                                const l = page.selected.slice()
                                l.splice(index - 1, 0, l.splice(index, 1)[0])
                                page.setWidgets(l)
                            }
                        }
                    }
                    Rectangle {
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.danger
                        Icon { anchors.centerIn: parent; name: "minus"; size: 16 }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: page.setWidgets(page.selected.filter((k, i) => i !== index))
                        }
                    }
                }
            }
        }
    }

    ListGroup {
        title: "Available widgets"
        Repeater {
            model: page.available.filter(w => !page.selected.includes(w.key))
            delegate: ListItem {
                required property var modelData
                readonly property bool fits: page.usedUnits + page.unitsOf(modelData) <= page.maxUnits
                text: modelData.name
                subtitle: modelData.appName + " • " + (modelData.size === "wide" ? "Wide" : "Small")
                iconSource: modelData.iconUrl
                enabled: fits
                onClicked: page.setWidgets(page.selected.concat([modelData.key]))
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    color: "#30D158"
                    Icon { anchors.centerIn: parent; name: "plus"; size: 16 }
                }
            }
        }
    }

    ListGroup {
        title: "Security"
        ListItem {
            text: "Lock Screen PIN"
            value: Lock.hasPin ? "On" : "Off"
            chevron: true
            separator: false
            onClicked: stack.open(Qt.resolvedUrl("PinPage.qml"))
        }
    }

    Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Tip: long press the lock screen to come back here. Apps can add their own widgets by declaring them in their app.json."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.textTertiary
    }
}
