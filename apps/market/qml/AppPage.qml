// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// One app: header with the GET button, screenshots, description, what's new
// and information.
Page {
    id: page
    property var store
    property var entry
    property var details: null      // /api/store/apps/<package>
    property bool more: false
    title: ""
    Component.onCompleted: store.get("/api/store/apps/" + encodeURIComponent(entry.package), function(d) { page.details = d })

    Row {
        width: parent.width
        spacing: 16
        AppIcon { size: 118; source: page.entry.icon || "" }
        Column {
            width: parent.width - 134
            spacing: 4
            Text { width: parent.width; wrapMode: Text.WordWrap; text: page.entry.name; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            Text { width: parent.width; elide: Text.ElideRight; text: page.details ? page.details.developer : page.entry.category; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            Item { width: 1; height: 16 }
            GetButton { store: page.store; entry: page.entry; prominent: true }
        }
    }
    Row {
        width: parent.width
        Repeater {
            model: [
                { k: qsTr("SIZE"), v: page.store.size(page.entry.size || 0) },
                { k: qsTr("CATEGORY"), v: page.entry.category || "" },
                { k: qsTr("VERSION"), v: page.entry.version || "" },
                { k: qsTr("DOWNLOADS"), v: page.details ? String(page.details.downloads) : "–" }
            ]
            delegate: Column {
                required property var modelData
                width: page.width / 4 - 10
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.k; font.family: Theme.fontFamily; font.pixelSize: 10; font.weight: Font.Bold; color: Theme.textTertiary }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.v; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.textSecondary }
            }
        }
    }
    ListView {
        visible: !!page.details && page.details.screenshots.length > 0
        width: parent.width
        height: 420
        orientation: ListView.Horizontal
        spacing: 12
        clip: true
        model: page.details ? page.details.screenshots : []
        delegate: Image {
            required property string modelData
            height: 420
            fillMode: Image.PreserveAspectFit
            source: modelData
            asynchronous: true
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: page.more ? 1000 : 4
        elide: Text.ElideRight
        text: page.details ? (page.details.description || page.entry.summary) : (page.entry.summary || "")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.text
        MouseArea { anchors.fill: parent; onClicked: page.more = !page.more }
    }
    Column {
        visible: !!page.details && page.details.versions.length > 0
        width: parent.width
        spacing: 6
        Text { text: qsTr("What's New"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
        Text {
            text: page.details && page.details.versions.length ? qsTr("Version %1").arg(page.details.versions[0].version) : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.footnoteSize
            color: Theme.textSecondary
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: page.details && page.details.versions.length ? (page.details.versions[0].notes || qsTr("Improvements and fixes.")) : ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.text
        }
    }
    ListGroup {
        title: qsTr("Information")
        ListItem { text: qsTr("Developer"); value: page.details ? page.details.developer : ""; enabled: false }
        ListItem { text: qsTr("Package"); value: page.entry.package; enabled: false }
        ListItem { text: qsTr("Compatibility"); value: "astraOS"; enabled: false }
        ListItem {
            visible: !!page.details && !!page.details.website
            text: qsTr("Website")
            chevron: true
            onClicked: Packages.launch("com.astra.planet", { url: page.details.website })
        }
        ListItem {
            text: qsTr("Share")
            iconName: "share"
            separator: false
            onClicked: share.open([], "text/uri-list", "share", page.entry.page || page.store.server + "/store/" + page.entry.package)
        }
    }
    ShareSheet { id: share }
}
