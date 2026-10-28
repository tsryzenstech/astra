// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > About (AboutFinal.png): a colourful gradient, the astra
// wordmark with the version, the device card and More Settings.
Page {
    id: page
    title: qsTr("About")
    centeredTitle: true
    spacing: 16

    readonly property var info: System.info

    function gb(bytes) {
        return bytes ? (bytes / 1073741824).toFixed(1) + "GB" : "—"
    }

    background: Component {
        Canvas {
            // Soft violet, blue and green glows behind the logo, fading to black.
            onPaint: {
                const ctx = getContext("2d")
                ctx.fillStyle = "#000000"
                ctx.fillRect(0, 0, width, height)
                const glow = (x, y, r, color) => {
                    const g = ctx.createRadialGradient(x, y, 0, x, y, r)
                    g.addColorStop(0, color)
                    g.addColorStop(1, "rgba(0,0,0,0)")
                    ctx.fillStyle = g
                    ctx.fillRect(0, 0, width, height)
                }
                glow(width * 0.15, height * 0.2, width * 0.75, "rgba(110,40,120,0.55)")
                glow(width * 0.45, height * 0.33, width * 0.6, "rgba(50,60,150,0.45)")
                glow(width * 0.95, height * 0.18, width * 0.8, "rgba(10,120,90,0.55)")
            }
        }
    }

    Column {
        width: parent.width
        topPadding: 12
        bottomPadding: 18
        spacing: 0
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width * 0.68, 260)
            height: width * 102 / 360
            source: System.fileUrl("/system/media/brand/astra_white.svg")
            sourceSize: Qt.size(width * 2, height * 2)
            fillMode: Image.PreserveAspectFit
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: (page.info.version || System.version) + " “" + (page.info.codename || "Blossom") + "”"
            font.family: Theme.fontFamily
            font.pixelSize: 21
            font.weight: Font.Medium
            color: "white"
        }
    }

    // Device card
    Rectangle {
        width: parent.width
        height: specs.height + 52
        radius: Theme.cardRadius
        color: "#121212"

        Column {
            id: specs
            x: 22
            y: 24
            width: parent.width - phone.width - 52
            spacing: 6
            Text {
                width: parent.width + phone.width
                text: (page.info.deviceName || page.info.model || qsTr("astra phone")).toUpperCase()
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: 26
                font.weight: Font.DemiBold
                color: "white"
                bottomPadding: 10
            }
            Repeater {
                model: [
                    { label: qsTr("CPU"), value: page.info.cpu || "—" },
                    { label: qsTr("RAM"), value: page.gb(page.info.ram) },
                    { label: qsTr("STORAGE"), value: page.gb(page.info.storageTotal) },
                    { label: qsTr("ASTRAOS VERSION"), value: page.info.version || System.version },
                    { label: qsTr("KERNEL VERSION"), value: (page.info.kernel || "—").split("-")[0] }
                ]
                delegate: Column {
                    required property var modelData
                    width: specs.width
                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Qt.rgba(1, 1, 1, 0.5)
                    }
                    Text {
                        width: parent.width
                        text: modelData.value
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                }
            }
        }

        // White phone illustration
        Rectangle {
            id: phone
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 34
            width: 116
            height: 254
            radius: 18
            color: "#FFFFFF"
            border.width: 2
            border.color: "#E6E6E6"
            Rectangle {
                x: 8
                y: 7
                width: 28
                height: 74
                radius: 14
                color: "#0B0B0B"
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: 3
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: "#1D1D24"
                            border.width: 2
                            border.color: "#3A3A44"
                        }
                    }
                }
            }
            Rectangle { x: 41; y: 40; width: 5; height: 5; radius: 2.5; color: "#CFCFCF" }
            Rectangle { x: -3; y: 36; width: 3; height: 18; radius: 1.5; color: "#E6E6E6" }
            Rectangle { x: parent.width; y: 36; width: 3; height: 18; radius: 1.5; color: "#E6E6E6" }
        }
    }

    // More Settings
    Rectangle {
        width: parent.width
        height: 62
        radius: Theme.cardRadius - 4
        color: moreArea.pressed ? "#1C1C1C" : "#121212"
        Text {
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("More Settings")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize + 3
            font.weight: Font.Medium
            color: "white"
        }
        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-right"
            size: 26
        }
        MouseArea { id: moreArea; anchors.fill: parent; onClicked: stack.open(Qt.resolvedUrl("MoreAboutPage.qml")) }
    }
}
