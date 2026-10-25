// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// App Info: package details, open and uninstall.
Page {
    id: page

    property string packageName
    property var info: ({})
    property string message: ""

    title: info.name || "App Info"

    function load() {
        Packages.details(packageName, (result, error) => {
            if (result)
                info = result
            else
                message = error
        })
    }
    Component.onCompleted: load()

    function formatSize(bytes) {
        if (!bytes)
            return "—"
        return bytes > 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " KB"
    }

    Row {
        spacing: 16
        AppIcon { size: 76; source: page.info.iconUrl || "" }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: page.info.name || page.packageName
                font.family: Theme.fontFamily
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: Theme.text
            }
            Text {
                text: "Version " + (page.info.version || "?")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
        }
    }

    Row {
        spacing: 12
        Button { text: "Open"; onClicked: Packages.launch(page.packageName) }
        Button {
            text: "Uninstall"
            destructive: true
            enabled: page.info.removable === true
            onClicked: Packages.uninstall(page.packageName, (ok, error) => {
                if (ok)
                    page.stack.pop()
                else
                    page.message = error
            })
        }
    }

    Text {
        visible: page.info.system === true || page.message !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: page.message !== "" ? page.message : "System apps are installed by root and can't be uninstalled."
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.textTertiary
    }

    ListGroup {
        title: "Details"
        ListItem { text: "Package"; value: page.packageName }
        ListItem { text: "Installed by"; value: page.info.installer || "—" }
        ListItem { text: "Location"; value: page.info.privileged ? "priv-app" : page.info.system ? "system/app" : "data/app" }
        ListItem { text: "User ID"; value: page.info.uid !== undefined ? page.info.uid : "—" }
        ListItem { text: "Storage"; value: page.formatSize(page.info.sizeBytes) }
        ListItem { text: "Widgets"; value: page.info.widgets ? page.info.widgets.length : 0; separator: false }
    }

    ListGroup {
        title: "Permissions"
        visible: (page.info.permissions || []).length > 0
        Repeater {
            model: page.info.permissions || []
            delegate: ListItem {
                required property string modelData
                required property int index
                text: modelData.replace("astra.permission.", "").replace(/_/g, " ").toLowerCase()
                separator: index < page.info.permissions.length - 1
            }
        }
    }
}
