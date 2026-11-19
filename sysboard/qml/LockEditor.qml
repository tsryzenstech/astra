// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import Astra.Core
import Astra.Controls
import Astra.Animation

// Customising one lock screen: boxes around the date, the clock and the widgets. Touch the clock for
// its font and weight, drag the dot at its bottom right corner downwards to stretch it taller (up to
// the dotted box), touch the widgets to choose them, the picture at the bottom left for another
// wallpaper. Cancel leaves the lock screen as it was; Done keeps the changes.
Item {
    id: root

    property int slotId: 0
    property bool shown: false
    property Item blurSource: null
    signal finished()
    signal deleted()

    property var draft: ({})
    property string panel: ""            // "", "clock", "widgets"
    property bool choosing: false

    visible: reveal.value > 0.01
    opacity: reveal.value
    z: 65
    Spring { id: reveal; to: root.shown ? 1 : 0; response: 0.42; dampingFraction: 0.86 }

    onShownChanged: {
        if (shown) {
            draft = Object.assign({}, LockSlots.slots.find(s => s.id === slotId) || LockSlots.defaultSlot)
            panel = ""
            choosing = false
            menu.visible = false
        }
    }
    function change(changes) { draft = Object.assign({}, draft, changes) }

    readonly property var weights: ["Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "Black"]
    readonly property var families: [
        { name: "Poppins", family: "" }, { name: "Liberation Sans", family: "Liberation Sans" },
        { name: "DejaVu Sans", family: "DejaVu Sans" }, { name: "Liberation Serif", family: "Liberation Serif" },
        { name: "DejaVu Serif", family: "DejaVu Serif" }, { name: "Liberation Mono", family: "Liberation Mono" }
    ]
    readonly property var available: Packages.count >= 0 ? Packages.widgets.filter(w => !!w.size) : []
    function unitsOf(key) {
        const w = available.find(x => x.key === key)
        return w && w.size === "wide" ? 2 : 1
    }
    readonly property int usedUnits: (draft.widgets || []).reduce((n, k) => n + unitsOf(k), 0)

    // The face being edited.
    LockFace {
        id: face
        anchors.fill: parent
        slot: root.draft
        editing: true
        showLock: false
    }
    MouseArea { anchors.fill: parent; onClicked: { root.panel = ""; menu.visible = false } }

    // The limit of the clock's height: a dotted box.
    Rectangle {
        x: face.clockBox.x
        y: face.clockTop
        width: face.clockBox.width
        height: face.clockSize * 1.12 * face.maxStretch
        radius: 22
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, root.panel === "clock" || handle.dragging ? 0.3 : 0)
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    // Touch the clock: its font and weight.
    MouseArea {
        x: face.clockBox.x
        y: face.clockTop
        width: face.clockBox.width
        height: face.clockBoxHeight
        onClicked: root.panel = "clock"
    }
    // Touch the widgets: choose them.
    MouseArea {
        x: face.widgetsBox.x
        y: face.widgetsTop
        width: face.widgetsBox.width
        height: face.widgetsBox.height
        onClicked: root.panel = "widgets"
    }

    // The dot that stretches the clock.
    Rectangle {
        id: handle
        readonly property bool dragging: handleArea.pressed
        x: face.clockBox.x + face.clockBox.width - width / 2 - 4
        y: face.clockTop + face.clockBoxHeight - height / 2 - 4
        width: 30
        height: 30
        radius: 15
        color: Qt.rgba(1, 1, 1, 0.92)
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.2)
        scale: dragging ? 1.2 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Qt.rgba(0, 0, 0, 0.45) }
        MouseArea {
            id: handleArea
            anchors.fill: parent
            anchors.margins: -16
            property real startStretch: 1
            property real startY: 0
            onPressed: (m) => { startStretch = root.draft.stretch || 1; startY = mapToItem(root, m.x, m.y).y; root.panel = "clock" }
            onPositionChanged: (m) => {
                const dy = mapToItem(root, m.x, m.y).y - startY
                const s = startStretch + dy / (face.clockSize * 1.12)
                root.change({ stretch: Math.max(1, Math.min(face.maxStretch, s)) })
            }
        }
    }

    // ---- top bar -------------------------------------------------------------------------------
    Glass {
        x: 12
        y: Theme.statusBarHeight + 8
        width: 84
        height: 36
        source: root.blurSource
        onClicked: root.finished()
        Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
    }
    Glass {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: Theme.statusBarHeight + 8
        width: 76
        height: 36
        source: root.blurSource
        tint: Qt.rgba(1, 1, 1, 0.26)
        onClicked: {
            LockSlots.update(root.slotId, { wallpaper: root.draft.wallpaper, font: root.draft.font, weight: root.draft.weight,
                                            stretch: root.draft.stretch, widgets: root.draft.widgets })
            root.finished()
        }
        Text { anchors.centerIn: parent; text: qsTr("Done"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
    }

    // ---- bottom: the wallpaper, and more ---------------------------------------------------------------
    Rectangle {
        id: thumb
        x: 26
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.homeIndicatorHeight + 22 + (root.panel === "" ? 0 : options.height + 14)
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        width: 64
        height: 64
        radius: 16
        color: "transparent"
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: thumbMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image { anchors.fill: parent; source: face.wallpaperUrl; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(128, 228); asynchronous: true }
        }
        Rectangle { id: thumbMask; anchors.fill: parent; radius: 16; visible: false; layer.enabled: true }
        Rectangle { anchors.fill: parent; radius: 16; color: "transparent"; border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.7) }
        MouseArea { anchors.fill: parent; onClicked: root.choosing = true }
    }
    Glass {
        id: moreButton
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.verticalCenter: thumb.verticalCenter
        width: 48
        height: 48
        source: root.blurSource
        onClicked: menu.visible = !menu.visible
        Icon { anchors.centerIn: parent; name: "more"; size: 22; color: "white" }
    }
    Glass {
        id: menu
        visible: false
        clickable: false
        anchors.right: parent.right
        anchors.rightMargin: 26
        anchors.bottom: moreButton.top
        anchors.bottomMargin: 8
        width: 230
        height: root.slotId === 1 ? 52 : 104
        radius: 22
        source: root.blurSource
        tint: Qt.rgba(0.1, 0.1, 0.12, 0.55)
        Column {
            anchors.fill: parent
            Item {
                width: parent.width
                height: 52
                Text { anchors.verticalCenter: parent.verticalCenter; x: 18; text: qsTr("Reset the Clock"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: { root.change({ stretch: 1, weight: "SemiBold", font: "" }); menu.visible = false } }
            }
            Item {
                visible: root.slotId !== 1
                width: parent.width
                height: 52
                Text { anchors.verticalCenter: parent.verticalCenter; x: 18; text: qsTr("Delete This Lock Screen"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.danger }
                MouseArea { anchors.fill: parent; onClicked: { menu.visible = false; root.deleted() } }
            }
        }
    }

    // ---- the options for what was touched ------------------------------------------------------------
    Glass {
        id: options
        clickable: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.homeIndicatorHeight + 14
        width: parent.width - 40
        height: root.panel === "" ? 0 : (root.panel === "clock" ? 124 : Math.min(260, 58 + Math.max(1, root.available.length) * 48))
        visible: height > 1
        radius: 28
        source: root.blurSource
        tint: Qt.rgba(0.1, 0.1, 0.12, 0.45)
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // The clock: a face and a weight, in two rows that slide.
        Column {
            visible: root.panel === "clock"
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            Flickable {
                width: parent.width
                height: 40
                contentWidth: familyRow.width
                clip: true
                Row {
                    id: familyRow
                    spacing: 8
                    Repeater {
                        model: root.families
                        delegate: Rectangle {
                            id: famChip
                            required property var modelData
                            readonly property bool on: (root.draft.font || "") === modelData.family
                            width: famLabel.implicitWidth + 28
                            height: 38
                            radius: 19
                            color: on ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.16)
                            Text {
                                id: famLabel
                                anchors.centerIn: parent
                                text: famChip.modelData.name
                                font.family: famChip.modelData.family || Theme.fontFamily
                                font.pixelSize: Theme.bodySize - 1
                                color: famChip.on ? "black" : "white"
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.change({ font: famChip.modelData.family }) }
                        }
                    }
                }
            }
            Flickable {
                width: parent.width
                height: 40
                contentWidth: weightRow.width
                clip: true
                Row {
                    id: weightRow
                    spacing: 8
                    Repeater {
                        model: root.weights
                        delegate: Rectangle {
                            id: weightChip
                            required property string modelData
                            readonly property bool on: (root.draft.weight || "SemiBold") === modelData
                            width: weightLabel.implicitWidth + 28
                            height: 38
                            radius: 19
                            color: on ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.16)
                            Text {
                                id: weightLabel
                                anchors.centerIn: parent
                                text: weightChip.modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodySize - 1
                                color: weightChip.on ? "black" : "white"
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.change({ weight: weightChip.modelData }) }
                        }
                    }
                }
            }
        }

        // The widgets: tap to add or remove, four spaces in all.
        Column {
            visible: root.panel === "widgets"
            anchors.fill: parent
            anchors.margins: 14
            spacing: 4
            Text {
                text: qsTr("Widgets  %1/4").arg(root.usedUnits)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                font.weight: Font.DemiBold
                color: Qt.rgba(1, 1, 1, 0.75)
            }
            Repeater {
                model: root.available
                delegate: Item {
                    id: widgetRowItem
                    required property var modelData
                    readonly property bool on: (root.draft.widgets || []).indexOf(modelData.key) >= 0
                    readonly property bool fits: on || root.usedUnits + root.unitsOf(modelData.key) <= 4
                    width: parent.width
                    height: 44
                    opacity: fits ? 1 : 0.4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 40
                        elide: Text.ElideRight
                        text: widgetRowItem.modelData.name + "  ·  " + widgetRowItem.modelData.appName
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        color: "white"
                    }
                    Icon {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        name: widgetRowItem.on ? "check-circle" : "add-circle"
                        size: 24
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: widgetRowItem.fits
                        onClicked: {
                            const key = widgetRowItem.modelData.key
                            const now = root.draft.widgets || []
                            root.change({ widgets: widgetRowItem.on ? now.filter(k => k !== key) : now.concat([key]) })
                        }
                    }
                }
            }
        }
    }

    WallpaperChooser {
        anchors.fill: parent
        shown: root.choosing
        blurSource: root.blurSource
        onChosen: (path) => { root.change({ wallpaper: path }); root.choosing = false }
        onCancelled: root.choosing = false
    }
}
