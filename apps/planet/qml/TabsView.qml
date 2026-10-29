// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// All tabs as cards. Tap one to open it, swipe it sideways or tap × to
// close it; switch between normal and private tabs at the bottom.
Rectangle {
    id: root
    required property var browser
    property bool shown: false

    color: browser.privateMode ? "#16161B" : (Theme.light ? "#E4E4EA" : "#0E0E12")
    visible: reveal.value > 0.01
    opacity: Math.min(1, reveal.value * 1.4)
    Spring { id: reveal; to: root.shown ? 1 : 0; response: 0.36; dampingFraction: 0.86 }
    onShownChanged: reveal.animateTo(shown ? 1 : 0, 0)

    readonly property var list: browser.tabs.filter(t => t.isPrivate === browser.privateMode)

    function pick(t) {
        browser.current = browser.tabs.indexOf(t)
        browser.showTabs = false
    }

    MouseArea { anchors.fill: parent }

    GridView {
        id: grid
        anchors.top: parent.top
        anchors.topMargin: Theme.statusBarHeight + 12
        anchors.bottom: bottom.top
        x: 12
        width: parent.width - 24
        cellWidth: width / 2
        cellHeight: cellWidth * 1.45
        model: root.list
        scale: 0.92 + 0.08 * reveal.value
        clip: true
        delegate: Item {
            id: card
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight
            property real swipe: 0
            opacity: 1 - Math.min(1, Math.abs(swipe) / width)

            Item {
                anchors.fill: parent
                anchors.margins: 8
                transform: Translate { x: card.swipe }
                Rectangle {
                    id: shot
                    width: parent.width
                    height: parent.height - 26
                    radius: 18
                    color: Theme.surface
                    clip: true
                    border.width: card.modelData === root.browser.tab ? 3 : 0
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        visible: card.modelData.thumbnail.toString() === ""
                        text: root.browser.host(card.modelData.url).charAt(0).toUpperCase() || "+"
                        font.family: Theme.fontFamily
                        font.pixelSize: 44
                        font.weight: Font.Bold
                        color: Theme.textTertiary
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: shot.border.width
                        source: card.modelData.thumbnail
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        width: 26
                        height: 26
                        radius: 13
                        color: Qt.rgba(0, 0, 0, 0.55)
                        Icon { anchors.centerIn: parent; name: "close"; size: 14; color: "white" }
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.browser.closeTab(card.modelData) }
                    }
                }
                Row {
                    anchors.top: shot.bottom
                    anchors.topMargin: 6
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6
                    Image { width: 14; height: 14; source: card.modelData.icon; visible: status === Image.Ready; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: Math.min(implicitWidth, card.width - 40)
                        elide: Text.ElideRight
                        text: card.modelData.title
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.footnoteSize
                        color: root.browser.privateMode ? "white" : Theme.text
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.bottomMargin: 26
                anchors.topMargin: 44
                property real startX
                property bool dragging: false
                onPressed: (m) => { startX = m.x; dragging = false }
                onPositionChanged: (m) => {
                    if (!dragging && Math.abs(m.x - startX) > 14) { dragging = true; preventStealing = true }
                    if (dragging) card.swipe = m.x - startX
                }
                onReleased: {
                    preventStealing = false
                    if (dragging && Math.abs(card.swipe) > card.width * 0.4)
                        root.browser.closeTab(card.modelData)
                    else if (!dragging)
                        root.pick(card.modelData)
                    card.swipe = 0
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: grid
        visible: root.list.length === 0
        iconName: root.browser.privateMode ? "eye-off" : "tabs"
        title: root.browser.privateMode ? qsTr("Private Browsing") : qsTr("No Tabs")
        message: root.browser.privateMode ? qsTr("Open a private tab: Planet won't remember your history and deletes its cookies when you close it.") : ""
    }

    Rectangle {
        id: bottom
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64 + Theme.homeIndicatorHeight * 0.6
        color: "transparent"
        Item {
            x: 12
            y: 8
            width: parent.width - 24
            height: 44
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                font.family: Theme.fontFamily
                font.pixelSize: 34
                font.weight: Font.Light
                color: root.browser.privateMode ? "white" : Theme.accent
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -14
                    onClicked: {
                        root.browser.newTab("", root.browser.privateMode)
                        root.browser.showTabs = false
                        root.browser.editing = true
                    }
                }
            }
            SegmentedControl {
                anchors.centerIn: parent
                width: 210
                model: [qsTr("Private"), qsTr("%n Tabs", "", root.browser.tabs.filter(t => !t.isPrivate).length)]
                currentIndex: root.browser.privateMode ? 0 : 1
                onActivated: (i) => root.browser.privateMode = i === 0
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Done")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: root.browser.privateMode ? "white" : Theme.accent
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    onClicked: {
                        const same = root.list
                        if (same.length && same.indexOf(root.browser.tab) < 0)
                            root.browser.current = root.browser.tabs.indexOf(same[0])
                        else if (!same.length)
                            root.browser.newTab("", root.browser.privateMode)
                        root.browser.showTabs = false
                    }
                }
            }
        }
    }
}
