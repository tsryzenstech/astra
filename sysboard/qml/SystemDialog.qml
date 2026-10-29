// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Bottom sheet popups with up to three buttons: permission requests, USB
// debugging authorisation, and Dialogs.show() from apps. One at a time;
// the rest wait in line. Tapping outside picks the first (cancel) button.
Item {
    id: root

    property var queue: []
    property var current: null
    readonly property bool active: current !== null

    visible: reveal.value > 0.005
    Spring { id: reveal; to: 0; response: 0.42; dampingFraction: 0.78 }

    function enqueue(d) {
        for (const q of queue)
            if (q.id === d.id)
                return
        if (current && current.id === d.id)
            return
        queue = queue.concat([d])
        if (!current)
            next()
    }
    function next() {
        if (queue.length === 0) {
            current = null
            reveal.animateTo(0, 0)
            return
        }
        current = queue[0]
        queue = queue.slice(1)
        reveal.snap(0)
        reveal.animateTo(1, 0)
    }
    function answer(button) {
        if (!current)
            return
        Dialogs.answer(current.id, button)
        dismissCurrent()
    }
    function dismissCurrent() {
        current = null
        reveal.animateTo(0, 0)
        nextTimer.restart()
    }
    function removed(id) {
        if (current && current.id === id)
            dismissCurrent()
        else
            queue = queue.filter(q => q.id !== id)
    }
    Timer { id: nextTimer; interval: 260; onTriggered: if (!root.current) root.next() }

    Connections {
        target: Dialogs
        function onShown(d) { root.enqueue(d) }
        function onClosed(id) { root.removed(id) }
    }
    Component.onCompleted: Dialogs.pending(function(list) { for (const d of (list || [])) root.enqueue(d) })

    // Presentation of the well-known kinds, translated here.
    readonly property var view: {
        const d = current
        if (!d)
            return { title: "", message: "", icon: "", buttons: [] }
        const buttons = (d.buttons || []).map(b => ({ id: b.id, label: Catalog.tr(b.label), style: b.style || "" }))
        if (d.kind === "permission") {
            return { title: qsTr("Allow %1 to access %2?").arg(d.appName || d.package).arg(Catalog.tr(d.label).toLowerCase()),
                     message: qsTr("You can change this later in Settings > Apps > %1.").arg(d.appName || d.package),
                     icon: d.icon || "shield", appIcon: d.appIcon, buttons: buttons }
        }
        if (d.kind === "usb-debugging") {
            const details = d.details || {}
            return { title: qsTr("Allow USB debugging?"),
                     message: qsTr("%1 wants to manage this device. Only allow computers you trust.\nKey fingerprint: %2")
                              .arg(details.computer || qsTr("A computer")).arg(details.fingerprint || ""),
                     icon: "usb", buttons: buttons }
        }
        return { title: d.title || "", message: d.message || "", icon: d.icon || "", appIcon: d.fromApp ? d.appIcon : "",
                 buttons: buttons }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45 * Math.min(1, reveal.value)
        MouseArea {
            anchors.fill: parent
            enabled: root.active
            // Permission requests can only be answered with their buttons.
            onClicked: {
                if (root.modal)
                    return
                const b = root.view.buttons
                root.answer(b.length ? b[0].id : "")
            }
        }
    }

    // Permission requests: a card in the middle of the screen that pops in
    // and cannot be dismissed. Everything else: a bottom sheet.
    readonly property bool modal: !!current && current.kind === "permission"

    Rectangle {
        id: sheet
        x: root.modal ? 28 : 10
        width: parent.width - (root.modal ? 56 : 20)
        height: column.implicitHeight + 48
        y: root.modal ? (parent.height - height) / 2 : parent.height - 12 - height + (1 - reveal.value) * (height + 40)
        scale: root.modal ? 0.8 + 0.2 * reveal.value : 1
        opacity: root.modal ? Math.min(1, reveal.value * 1.5) : 1
        radius: Theme.sheetRadius
        color: Theme.sheet
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)

        MouseArea { anchors.fill: parent } // keeps taps inside the sheet

        Column {
            id: column
            x: 22
            y: 26
            width: parent.width - 44
            spacing: 14

            // App icon with the request's symbol badge, or the symbol alone.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                visible: !!root.view.icon || !!root.view.appIcon
                AppIcon {
                    visible: !!root.view.appIcon
                    anchors.fill: parent
                    size: 64
                    // astrad sends a file path
                    source: root.view.appIcon ? (String(root.view.appIcon).startsWith("/") ? "file://" + root.view.appIcon : root.view.appIcon) : ""
                }
                Rectangle {
                    visible: !!root.view.icon
                    width: root.view.appIcon ? 30 : 64
                    height: width
                    radius: width / 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.rightMargin: root.view.appIcon ? -6 : 0
                    anchors.bottomMargin: root.view.appIcon ? -6 : 0
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accentDeep }
                    }
                    border.width: root.view.appIcon ? 3 : 0
                    border.color: sheet.color
                    Icon { anchors.centerIn: parent; name: root.view.icon || ""; size: parent.width * 0.52 }
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.view.title
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 2
                font.weight: Font.DemiBold
                color: Theme.text
            }
            Text {
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.view.message
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                color: Theme.textSecondary
                lineHeight: 1.15
            }

            Item { width: 1; height: 2 }

            // Two buttons side by side, otherwise stacked.
            Grid {
                width: parent.width
                columns: root.view.buttons.length === 2 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: root.view.buttons
                    delegate: Rectangle {
                        id: button
                        required property var modelData
                        width: root.view.buttons.length === 2 ? (column.width - 10) / 2 : column.width
                        height: 50
                        radius: 25
                        readonly property bool primary: modelData.style === "primary"
                        readonly property bool destructive: modelData.style === "destructive"
                        color: destructive ? Theme.danger : primary ? Theme.accent : Theme.surfaceRaised
                        scale: area.pressed ? 0.95 : 1
                        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: button.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            font.weight: Font.DemiBold
                            color: button.primary || button.destructive ? Theme.accentText : Theme.text
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            onClicked: root.answer(button.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
