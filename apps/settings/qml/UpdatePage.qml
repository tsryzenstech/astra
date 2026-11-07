// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Software Update (docs/VERSIONING.md): the device repository's GitHub
// releases of the chosen channel. A newer one downloads, unpacks and is written
// by the phone itself while it restarts.
Page {
    id: page
    title: qsTr("Software Update")

    readonly property var u: Updates.state
    readonly property var available: u.available || {}
    readonly property string status: u.status || "idle"
    readonly property bool busy: status === "checking" || status === "downloading" || status === "preparing" || status === "installing"

    function channelName(c) {
        switch (c) {
        case "prerelease": return qsTr("Pre-release")
        case "stable": return qsTr("Stable")
        case "local": return qsTr("Local build")
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
                text: "“" + (page.u.codename || "") + "” • " + page.channelName(page.u.buildChannel)
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
                    case "preparing": return qsTr("Preparing the update…")
                    case "ready": return qsTr("astraOS %1 is ready to install. The phone restarts and installs it in a few minutes: keep it charged.").arg(page.available.version || "")
                    case "installing": return qsTr("Restarting to install…")
                    case "error": return page.u.error || qsTr("The update server could not be reached.")
                    }
                    return qsTr("Check for a newer version on the %1 channel.").arg(page.channelName(page.u.channel))
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.Medium
                color: "white"
            }
            ProgressBar {
                visible: page.busy
                width: parent.width
                height: 8
                indeterminate: page.status !== "downloading"
                value: page.u.progress || 0
                color: "white"
                trackColor: Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }

    Button {
        width: parent.width
        visible: !page.busy
        text: page.status === "available" ? qsTr("Download")
            : page.status === "ready" ? qsTr("Install and restart")
            : qsTr("Check for updates")
        onClicked: Updates.call(page.status === "available" ? "download" : page.status === "ready" ? "install" : "check", {}, null)
    }
    Button {
        width: parent.width
        visible: page.status === "downloading" || page.status === "ready"
        primary: false
        text: page.status === "ready" ? qsTr("Delete the download") : qsTr("Cancel")
        onClicked: Updates.call("cancel", {}, null)
    }

    ListGroup {
        visible: !!page.available.version && (page.status === "available" || page.status === "ready" || page.busy)
        title: qsTr("What's new")
        ListItem { text: qsTr("Version"); value: (page.available.version || "") + (page.available.codename ? " “" + page.available.codename + "”" : "") }
        ListItem {
            text: qsTr("Download size")
            value: page.available.size ? (page.available.size / 1e6).toFixed(0) + " MB" : "—"
            separator: (page.available.notes || []).length > 0
        }
        Column {
            visible: (page.available.notes || []).length > 0
            x: 16
            width: parent.width - 32
            topPadding: 8
            bottomPadding: 14
            spacing: 6
            Repeater {
                model: page.available.notes || []
                delegate: Text {
                    required property string modelData
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "•  " + modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize + 1
                    color: Theme.textSecondary
                }
            }
        }
    }

    ListGroup {
        title: qsTr("Channel")
        footer: qsTr("Pre-releases are the automatic builds of each change: they arrive first and may have problems. Stable has the releases only.")
        ListItem {
            text: qsTr("Stable")
            selected: page.u.channel === "stable"
            onClicked: if (!page.busy && page.u.channel !== "stable") Updates.call("setChannel", { channel: "stable" }, null)
        }
        ListItem {
            text: qsTr("Pre-release")
            separator: false
            selected: page.u.channel === "prerelease"
            onClicked: if (!page.busy && page.u.channel !== "prerelease") Updates.call("setChannel", { channel: "prerelease" }, null)
        }
    }

    ListGroup {
        title: qsTr("This build")
        ListItem { text: qsTr("Release"); value: page.u.tag || page.channelName("local") }
        ListItem { text: qsTr("Build ID"); value: page.u.buildId || "—" }
        ListItem { text: qsTr("Updates from"); value: page.u.repository || "—" }
        ListItem {
            text: qsTr("What's new")
            chevron: true
            onClicked: Packages.launch("com.astra.tips", { page: "changelog" })
        }
        ListItem {
            text: qsTr("Last checked")
            value: page.u.lastCheck ? Qt.locale().toString(new Date(page.u.lastCheck), "d MMM, HH:mm") : qsTr("Never")
            separator: false
        }
    }
}
