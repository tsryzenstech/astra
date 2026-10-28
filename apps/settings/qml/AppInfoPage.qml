// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// App Info: open, force stop, clear data, uninstall, notifications,
// permissions and storage of one app.
Page {
    id: page

    property string packageName
    property var info: ({})
    property var permissions: []
    property string message: ""

    title: info.name || qsTr("App Info")

    function load() {
        Packages.details(packageName, (result, error) => {
            if (result)
                info = result
            else
                message = error
        })
        Permissions.forPackage(packageName, function(list) { page.permissions = list || [] })
    }
    Component.onCompleted: load()
    Connections {
        target: Permissions
        function onChanged() { page.load() }
    }

    readonly property var runtimePerms: permissions.filter(p => p.level === "runtime" && p.name !== "astra.permission.NOTIFICATIONS")
    readonly property var notificationPerm: permissions.find(p => p.name === "astra.permission.NOTIFICATIONS")
    readonly property var otherPerms: permissions.filter(p => p.level !== "runtime")

    function formatSize(bytes) {
        if (!bytes)
            return "0 KB"
        return bytes > 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(bytes / 1024)) + " KB"
    }
    function confirm(title, message, button, action) {
        Dialogs.show({ title: title, message: message, icon: "warning",
                       buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "ok", label: button, style: "destructive" } ] },
                     function(b) { if (b === "ok") action() })
    }

    Column {
        width: parent.width
        spacing: 10
        AppIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 88; source: page.info.iconUrl || "" }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: page.info.name || page.packageName
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("Version %1").arg(page.info.version || "?")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.textSecondary
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        Repeater {
            model: [
                { id: "open", icon: "arrow-up", label: qsTr("Open") },
                { id: "stop", icon: "close", label: qsTr("Force stop") },
                { id: "uninstall", icon: "trash", label: qsTr("Uninstall"), danger: true }
            ]
            delegate: Card {
                required property var modelData
                width: 104
                height: 76
                padding: 10
                pressable: modelData.id !== "uninstall" || page.info.removable === true
                opacity: pressable ? 1 : 0.4
                Column {
                    width: parent.width
                    spacing: 6
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 22; color: modelData.danger ? Theme.danger : Theme.accent }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.label
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.captionSize
                        font.weight: Font.Medium
                        color: modelData.danger ? Theme.danger : Theme.text
                    }
                }
                onClicked: {
                    if (modelData.id === "open") {
                        Packages.launch(page.packageName)
                    } else if (modelData.id === "stop") {
                        page.confirm(qsTr("Force stop %1?").arg(page.info.name), qsTr("If you force stop an app, it may misbehave."),
                                     qsTr("Force stop"), () => System.call("activity.stop", { package: page.packageName }, null))
                    } else {
                        page.confirm(qsTr("Uninstall %1?").arg(page.info.name), qsTr("The app and all of its data will be removed from this phone."),
                                     qsTr("Uninstall"), () => Packages.uninstall(page.packageName, (ok, error) => {
                                         if (ok)
                                             page.stack.pop()
                                         else
                                             page.message = error
                                     }))
                    }
                }
            }
        }
    }

    Text {
        visible: page.info.system === true || page.message !== ""
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: page.message !== "" ? page.message : qsTr("Can't uninstall System Apps")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.textTertiary
    }

    ListGroup {
        visible: page.notificationPerm !== undefined
        title: qsTr("Notifications")
        ListItem {
            text: qsTr("Allow notifications")
            iconName: "notification"
            showSwitch: true
            separator: false
            checked: page.notificationPerm ? page.notificationPerm.state === "granted" : false
            onToggled: (on) => Permissions.set(page.packageName, "astra.permission.NOTIFICATIONS", on ? "granted" : "denied")
        }
    }

    ListGroup {
        visible: page.runtimePerms.length > 0
        title: qsTr("Permissions")
        Repeater {
            model: page.runtimePerms
            delegate: ListItem {
                required property var modelData
                required property int index
                text: Catalog.tr(modelData.label)
                subtitle: modelData.state === "granted" ? qsTr("Allowed") : modelData.state === "denied" ? qsTr("Not allowed") : qsTr("Ask every time")
                iconName: modelData.icon
                chevron: true
                separator: index < page.runtimePerms.length - 1
                onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                    title: Catalog.tr(modelData.label),
                    current: modelData.state,
                    popOnPick: true,
                    options: [ { value: "granted", label: qsTr("Allow") },
                               { value: "ask", label: qsTr("Ask every time") },
                               { value: "denied", label: qsTr("Don't allow") } ]
                }).picked.connect((v) => Permissions.set(page.packageName, modelData.name, v))
            }
        }
    }

    ListGroup {
        title: qsTr("Storage")
        ListItem { text: qsTr("App"); value: page.formatSize(page.info.codeBytes) }
        ListItem { text: qsTr("User data"); value: page.formatSize(page.info.dataBytes) }
        ListItem {
            text: qsTr("Clear data")
            destructive: true
            separator: false
            onClicked: page.confirm(qsTr("Clear the data of %1?").arg(page.info.name),
                                    qsTr("Files, accounts and settings of the app are deleted for good."),
                                    qsTr("Clear data"),
                                    () => System.call("packages.clearData", { package: page.packageName }, function() { page.load() }))
        }
    }

    ListGroup {
        title: qsTr("Details")
        ListItem { text: qsTr("Package"); value: page.packageName }
        ListItem { text: qsTr("Installed by"); value: page.info.installer || "—" }
        ListItem { text: qsTr("Location"); value: page.info.privileged ? "priv-app" : page.info.system ? "system/app" : "data/app" }
        ListItem { text: qsTr("User ID"); value: page.info.uid !== undefined ? page.info.uid : "—" }
        ListItem { text: qsTr("Widgets"); value: page.info.widgets ? page.info.widgets.length : 0; separator: page.otherPerms.length > 0 }
        Repeater {
            model: page.otherPerms
            delegate: ListItem {
                required property var modelData
                required property int index
                text: Catalog.tr(modelData.label)
                subtitle: modelData.level === "privileged" ? qsTr("System permission") : qsTr("Granted at install")
                iconName: modelData.icon
                separator: index < page.otherPerms.length - 1
            }
        }
    }
}
