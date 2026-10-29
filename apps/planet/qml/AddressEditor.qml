// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Typing an address or a search: the field sits above the keyboard, with
// search suggestions, matching bookmarks and history above it.
Rectangle {
    id: root
    required property var browser
    property bool active: false
    signal done()

    color: Theme.background
    visible: fade.value > 0.01
    opacity: fade.value
    Spring { id: fade; to: root.active ? 1 : 0; response: 0.3; dampingFraction: 1 }
    onActiveChanged: {
        fade.animateTo(active ? 1 : 0, 0)
        if (active) {
            input.text = browser.tab && browser.tab.started ? browser.tab.url : ""
            input.selectAll()
            input.forceActiveFocus()
            Qt.inputMethod.show()
            suggestions = []
        } else {
            input.focus = false
        }
    }

    property var suggestions: []
    readonly property var local: {
        const q = input.text.trim().toLowerCase()
        if (!q)
            return []
        const seen = {}
        const out = []
        for (const b of browser.bookmarks)
            if ((b.title + " " + b.url).toLowerCase().indexOf(q) >= 0 && !seen[b.url]) { seen[b.url] = 1; out.push({ kind: "bookmark", title: b.title, url: b.url }) }
        for (const h of browser.history)
            if ((h.title + " " + h.url).toLowerCase().indexOf(q) >= 0 && !seen[h.url]) { seen[h.url] = 1; out.push({ kind: "history", title: h.title, url: h.url }) }
        return out.slice(0, 5)
    }

    Timer {
        id: suggestTimer
        interval: 160
        onTriggered: {
            const q = input.text.trim()
            const e = root.browser.engines[root.browser.engine]
            if (!q || !e.suggest || /^[a-z]+:\/\//i.test(q) || (root.browser.tab && root.browser.tab.isPrivate)) {
                root.suggestions = []
                return
            }
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200)
                    return
                try {
                    const r = JSON.parse(xhr.responseText)
                    if (input.text.trim() === q)
                        root.suggestions = (r[1] || []).slice(0, 6)
                } catch (err) {}
            }
            xhr.open("GET", e.suggest + encodeURIComponent(q))
            xhr.send()
        }
    }

    function go(text) {
        if (!text.trim())
            return
        browser.open(text)
        done()
    }

    MouseArea { anchors.fill: parent }

    Flickable {
        id: results
        anchors.top: parent.top
        anchors.topMargin: Theme.statusBarHeight + 8
        anchors.bottom: field.top
        width: parent.width
        contentHeight: Math.max(height, list.height + 12)
        clip: true

        Column {
            id: list
            x: 16
            // Results sit just above the field, like the keyboard they follow.
            y: Math.max(0, results.height - height - 12)
            width: parent.width - 32
            spacing: 18

            Column {
                visible: input.text.trim() === ""
                width: parent.width
                spacing: 12
                Text { text: qsTr("Favorites"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                Flow {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: root.browser.bookmarks.slice(0, 12)
                        delegate: Rectangle {
                            required property var modelData
                            width: label.implicitWidth + 28
                            height: 36
                            radius: 18
                            color: Theme.surfaceRaised
                            Text { id: label; anchors.centerIn: parent; text: modelData.title || root.browser.host(modelData.url); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.text }
                            MouseArea { anchors.fill: parent; onClicked: root.go(modelData.url) }
                        }
                    }
                }
            }

            ListGroup {
                visible: root.suggestions.length > 0
                title: qsTr("%1 Search").arg(root.browser.engines[root.browser.engine].name)
                width: parent.width
                Repeater {
                    model: root.suggestions
                    delegate: ListItem {
                        required property string modelData
                        required property int index
                        text: modelData
                        iconName: "search"
                        separator: index < root.suggestions.length - 1
                        onClicked: root.go(modelData)
                    }
                }
            }
            ListGroup {
                visible: root.local.length > 0
                title: qsTr("Bookmarks and History")
                width: parent.width
                Repeater {
                    model: root.local
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.title || root.browser.host(modelData.url)
                        subtitle: root.browser.host(modelData.url)
                        iconName: modelData.kind === "bookmark" ? "bookmark" : "history"
                        separator: index < root.local.length - 1
                        onClicked: root.go(modelData.url)
                    }
                }
            }
        }
    }

    Rectangle {
        id: field
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64 + Theme.homeIndicatorHeight * 0.6
        color: Theme.glassPanel

        Rectangle {
            x: 14
            y: 9
            width: parent.width - 28 - cancel.width - 10
            height: 46
            radius: 23
            color: Theme.surfaceRaised
            Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textSecondary }
            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 42
                anchors.rightMargin: 40
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
                selectionColor: Theme.accent
                selectByMouse: true
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.type: Qt.EnterKeyGo
                onTextEdited: suggestTimer.restart()
                onAccepted: root.go(text)
            }
            Text {
                anchors.fill: input
                verticalAlignment: Text.AlignVCenter
                visible: input.text === ""
                text: qsTr("Search %1 or enter website").arg(root.browser.engines[root.browser.engine].name)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.textTertiary
                elide: Text.ElideRight
            }
            Icon {
                visible: input.text !== ""
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "close"
                size: 18
                color: Theme.textSecondary
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { input.text = ""; root.suggestions = []; input.forceActiveFocus() } }
            }
        }
        Text {
            id: cancel
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 9
            height: 46
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Cancel")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.done() }
        }
    }
}
