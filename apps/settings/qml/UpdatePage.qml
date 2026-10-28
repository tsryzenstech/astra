// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Software Update (docs/VERSIONING.md): checks the update server
// of this build's channel and downloads newer builds.
Page {
    id: page
    title: qsTr("Software Update")

    readonly property var u: Updates.state
    readonly property var available: u.available || {}
    readonly property string status: u.status || "idle"

    function channelName(c) {
        switch (c) {
        case "delta": return qsTr("Delta (preview)")
        case "beta": return qsTr("Beta")
        case "stable": return qsTr("Stable")
        }
        return c || "—"
    }

    Card {
        accented: true
        Column {
            width: parent.width
            spacing: 4
            Text {
                text: "astraOS " + (page.u.version || System.version)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize + 4
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                text: "“" + (page.u.codename || "") + "” • " + qsTr("build %1").arg(page.u.build || 0)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Qt.rgba(1, 1, 1, 0.9)
            }
            Item { width: 1; height: 8 }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: {
                    switch (page.status) {
                    case "checking": return qsTr("Checking for updates…")
                    case "uptodate": return qsTr("Your phone is up to date.")
                    case "available": return qsTr("astraOS %1 is available.").arg(page.available.version || "")
                    case "downloading": return qsTr("Downloading… %1%").arg(Math.round((page.u.progress || 0) * 100))
                    case "ready": return qsTr("The update is downloaded and verified.")
                    case "error": return page.u.error || qsTr("The update server could not be reached.")
                    }
                    return qsTr("Check for a newer build of your channel.")
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.Medium
                color: "white"
            }
            ProgressBar {
                visible: page.status === "downloading" || page.status === "checking"
                width: parent.width
                height: 8
                indeterminate: page.status === "checking"
                value: page.u.progress || 0
                color: "white"
                trackColor: Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }

    Button {
        width: parent.width
        visible: page.status !== "downloading" && page.status !== "ready"
        enabled: page.status !== "checking"
        text: page.status === "available" ? qsTr("Download") : qsTr("Check for updates")
        onClicked: Updates.call(page.status === "available" ? "download" : "check", {}, null)
    }
    Button {
        width: parent.width
        visible: page.status === "downloading"
        primary: false
        text: qsTr("Cancel")
        onClicked: Updates.call("cancel", {}, null)
    }

    ListGroup {
        visible: page.status === "available" || page.status === "ready" || page.status === "downloading"
        title: qsTr("What's new")
        footer: page.status === "ready" ? qsTr("Installing needs the astraOS recovery, which arrives with a later build. The package stays in /data/ota until then.") : ""
        ListItem { text: qsTr("Version"); value: (page.available.version || "") + (page.available.codename ? " “" + page.available.codename + "”" : "") }
        ListItem {
            text: qsTr("Size")
            value: page.available.size ? (page.available.size / 1e6).toFixed(0) + " MB" : "—"
            separator: !!page.available.notes
        }
        Text {
            visible: !!page.available.notes
            x: 16
            width: parent.width - 32
            topPadding: 8
            bottomPadding: 14
            wrapMode: Text.Wrap
            text: page.available.notes || ""
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize + 1
            color: Theme.textSecondary
        }
    }

    ListGroup {
        title: qsTr("This build")
        ListItem { text: qsTr("Channel"); value: page.channelName(page.u.channel) }
        ListItem { text: qsTr("Build ID"); value: page.u.buildId || "—" }
        ListItem {
            text: qsTr("Last checked")
            value: page.u.lastCheck ? Qt.formatDateTime(new Date(page.u.lastCheck), "d MMM, HH:mm") : qsTr("Never")
            separator: false
        }
    }
}
