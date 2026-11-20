// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Search of astraOS Desktop (Windows+Space, or Meta+Space): a bar in the middle of the screen that rises over the desktop
// (nothing is blurred under it). It finds apps, files (in the user's storage), a quick calculation, and anything else it hands to
// Planet as a web search. Up and Down choose, Return opens, Escape closes.
Item {
    id: root

    property var shell
    property Item blurSource
    property bool opened: false
    readonly property real reveal: spring.value
    property int current: 0

    visible: reveal > 0.002
    Spring { id: spring; to: root.opened ? 1 : 0; response: 0.36; dampingFraction: 0.82 }

    function open() {
        field.text = ""
        current = 0
        opened = true
        field.forceActiveFocus()
    }
    function close() { opened = false; field.focus = false }
    function toggle() { opened ? close() : open() }

    readonly property string query: field.text.trim()

    // Files: searched a moment after the typing stops (it reads the disk).
    property var fileHits: []
    Timer {
        id: fileTimer
        interval: 220
        onTriggered: {
            const q = root.query
            root.fileHits = q.length >= 2 && !Host.installer ? Files.search(Files.home, q, 6) : []
        }
    }
    onQueryChanged: { current = 0; fileHits = []; fileTimer.restart() }

    function calculation(text) {
        if (!/^[0-9+\-*/().,%^ ]+$/.test(text) || !/[+\-*/%^]/.test(text.replace(/^[-+]/, "")))
            return null
        try {
            const value = Number(eval(text.replace(/,/g, ".").replace(/\^/g, "**")))
            return isFinite(value) ? value : null
        } catch (e) {
            return null
        }
    }

    readonly property var results: {
        const q = query.toLowerCase()
        const out = []
        if (q === "")
            return out
        const sum = calculation(query)
        if (sum !== null)
            out.push({ kind: "calc", title: String(Math.round(sum * 1e9) / 1e9), subtitle: qsTr("Result of %1").arg(query), glyph: "calculator", value: sum })
        if (Packages.count >= 0) {
            const apps = Packages.list()
                .filter(p => p.launcher !== false && (p.name || "").toLowerCase().indexOf(q) >= 0)
                .sort((a, b) => {
                    const sa = (a.name || "").toLowerCase().startsWith(q) ? 0 : 1
                    const sb = (b.name || "").toLowerCase().startsWith(q) ? 0 : 1
                    return sa - sb || (a.name || "").localeCompare(b.name || "")
                })
            for (const a of apps.slice(0, 5))
                out.push({ kind: "app", title: a.name, subtitle: qsTr("Application"), icon: a.iconUrl || "", package: a.package })
        }
        for (const f of fileHits) {
            const path = f.path || f
            const name = f.name || String(path).split("/").pop()
            out.push({ kind: "file", title: name, subtitle: String(path).replace(Files.home, "~"), glyph: f.isDir ? "folder" : "file", path: String(path), isDir: !!f.isDir })
        }
        out.push({ kind: "web", title: qsTr("Search the web for \"%1\"").arg(query), subtitle: "Planet", glyph: "globe", query: query })
        return out
    }

    function activate(r) {
        if (!r)
            return
        close()
        if (r.kind === "app")
            shell.launch(r.package, {}, null)
        else if (r.kind === "file")
            shell.launch("com.astra.files", { path: r.isDir ? r.path : r.path.substring(0, r.path.lastIndexOf("/")), select: r.path }, null)
        else if (r.kind === "web")
            shell.launch("com.astra.planet", { query: r.query }, null)
    }

    // (nothing is blurred or dimmed under the bar: the desktop stays as it is)
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Item {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        width: 640
        height: bar.height + (list.visible ? list.height + 10 : 0)
        y: Math.max(70, parent.height * 0.2) - (1 - Math.min(1, root.reveal)) * 24
        opacity: Math.min(1, root.reveal * 1.6)
        transformOrigin: Item.Top
        scale: 0.92 + 0.08 * Math.min(1.04, root.reveal)

        Rectangle {
            id: bar
            width: parent.width
            height: 60
            radius: 30
            color: Qt.rgba(0.1, 0.1, 0.12, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            Icon { x: 22; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 22; color: "white"; opacity: 0.8 }
            TextInput {
                id: field
                anchors.fill: parent
                anchors.leftMargin: 62
                anchors.rightMargin: 24
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: 22
                color: "white"
                clip: true
                onAccepted: root.activate(root.results[root.current])
                Keys.onEscapePressed: root.close()
                Keys.onDownPressed: root.current = Math.min(root.results.length - 1, root.current + 1)
                Keys.onUpPressed: root.current = Math.max(0, root.current - 1)
                Text {
                    visible: !field.text
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: qsTr("Search apps, files and the web")
                    font: field.font
                    color: Qt.rgba(1, 1, 1, 0.5)
                }
            }
        }

        Rectangle {
            id: list
            visible: root.results.length > 0
            anchors.top: bar.bottom
            anchors.topMargin: 10
            width: parent.width
            height: Math.min(8, root.results.length) * 56 + 16
            radius: 26
            color: Qt.rgba(0.1, 0.1, 0.12, 0.72)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)
            clip: true
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Column {
                x: 8; y: 8
                width: parent.width - 16
                Repeater {
                    model: root.results.slice(0, 8)
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: parent.width
                        height: 56
                        radius: 18
                        color: root.current === index ? Theme.accent : hover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        Item {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34
                            AppIcon { visible: !!row.modelData.icon; anchors.fill: parent; size: 34; source: row.modelData.icon || "" }
                            Icon { visible: !row.modelData.icon; anchors.centerIn: parent; name: row.modelData.glyph || "search"; size: 24; color: "white" }
                        }
                        Column {
                            x: 60
                            width: parent.width - 80
                            anchors.verticalCenter: parent.verticalCenter
                            Text { width: parent.width; elide: Text.ElideRight; text: row.modelData.title; font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.DemiBold; color: "white" }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: row.modelData.subtitle; font.family: Theme.fontFamily; font.pixelSize: 12; color: Qt.rgba(1, 1, 1, 0.65) }
                        }
                        HoverHandler { id: hover; onHoveredChanged: if (hovered) root.current = row.index }
                        TapHandler { onTapped: root.activate(row.modelData) }
                    }
                }
            }
        }
    }
}
