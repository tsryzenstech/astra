// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Market: apps for astraOS from the catalog of this build
// (ro.astra.market.url, a JSON list of { package, name, version, versionCode,
// description, icon, url, sha256, size, category }), installed apps, and
// .apkg files from Downloads.
Rectangle {
    id: app
    color: Theme.background

    property string tab: "discover"
    property var catalog: []
    property string catalogError: ""
    property bool loading: false
    property var installing: ({})       // package -> true
    property var localFiles: []
    readonly property var installed: Packages.count >= 0 ? Packages.list() : []

    function installedVersion(pkg) {
        const p = installed.find(i => i.package === pkg)
        return p ? (p.versionCode || 1) : 0
    }
    function load() {
        const url = System.property("ro.astra.market.url", "")
        if (!url) {
            catalogError = qsTr("This build has no Market catalog.")
            return
        }
        loading = true
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            app.loading = false
            if (xhr.status !== 200) {
                app.catalogError = xhr.status === 404 ? qsTr("The catalog is not published yet.") : qsTr("Market can't be reached. Check your connection.")
                return
            }
            try {
                const data = JSON.parse(xhr.responseText)
                app.catalog = Array.isArray(data) ? data : (data.apps || [])
                app.catalogError = ""
            } catch (e) {
                app.catalogError = qsTr("The catalog could not be read.")
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }
    function install(entry) {
        const busy = Object.assign({}, installing)
        busy[entry.package] = true
        installing = busy
        System.call("packages.installUrl", { url: entry.url, sha256: entry.sha256 || "" }, function(r, err) {
            const b = Object.assign({}, app.installing)
            delete b[entry.package]
            app.installing = b
            if (err)
                Dialogs.show({ title: qsTr("Couldn't install %1").arg(entry.name), message: err, icon: "warning",
                               buttons: [ { id: "ok", label: qsTr("OK") } ] })
        })
    }
    function scanFiles() {
        Permissions.check("astra.permission.MEDIA", function(ok) {
            if (ok)
                app.localFiles = Application.media(["*.apkg"])
        })
    }
    Component.onCompleted: {
        load()
        scanFiles()
        installShared(Application.args)
    }
    Connections {
        target: Application
        function onIntent(args) { app.installShared(args) }
    }
    // An .apkg opened from Files: confirm, then install.
    function installShared(args) {
        if (!args || !args.files || !args.files.length)
            return
        const path = args.files[0]
        Dialogs.show({ title: qsTr("Install this app?"), message: path.split("/").pop() + "
" + qsTr("Only install files from people you trust."),
                       icon: "download", buttons: [ { id: "c", label: qsTr("Cancel") }, { id: "i", label: qsTr("Install"), style: "primary" } ] },
                     function(b) {
                         if (b !== "i")
                             return
                         System.call("packages.install", { path: path }, function(r, err) {
                             Dialogs.show({ title: err ? qsTr("Couldn't install the app") : qsTr("App installed"), message: err || "",
                                            icon: err ? "warning" : "check-circle", buttons: [ { id: "ok", label: qsTr("OK") } ] })
                         })
                     })
    }

    component AppRow: ListItem {
        id: row
        property var entry: ({})
        readonly property int have: app.installedVersion(entry.package)
        readonly property bool update: have > 0 && (entry.versionCode || 1) > have
        text: entry.name || entry.package
        subtitle: entry.description || ""
        iconSource: entry.icon || ""
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: label.implicitWidth + 28
            height: 32
            radius: 16
            color: row.have > 0 && !row.update ? Theme.surfaceRaised : Theme.accent
            Spinner { anchors.centerIn: parent; size: 16; running: !!app.installing[row.entry.package] }
            Text {
                id: label
                visible: !app.installing[row.entry.package]
                anchors.centerIn: parent
                text: row.update ? qsTr("Update") : row.have > 0 ? qsTr("Open") : qsTr("Get")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                font.weight: Font.Bold
                color: row.have > 0 && !row.update ? Theme.text : Theme.accentText
            }
            MouseArea {
                anchors.fill: parent
                enabled: !app.installing[row.entry.package]
                onClicked: row.have > 0 && !row.update ? Packages.launch(row.entry.package) : app.install(row.entry)
            }
        }
    }

    Loader {
        anchors.fill: parent
        anchors.bottomMargin: 96
        sourceComponent: app.tab === "discover" ? discover : installedPage
    }

    // ---- Discover --------------------------------------------------------------------
    Component {
        id: discover
        Page {
            title: qsTr("Market")
            Card {
                accented: true
                Column {
                    width: parent.width
                    spacing: 4
                    Text { text: qsTr("Apps for astraOS"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: "white" }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: qsTr("Every app runs in its own sandbox and asks before using your camera, location or contacts.")
                           font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1; color: Qt.rgba(1, 1, 1, 0.9) }
                }
            }
            Spinner { visible: app.loading; running: app.loading; anchors.horizontalCenter: parent.horizontalCenter }
            EmptyState {
                visible: !app.loading && app.catalog.length === 0
                iconName: "bag"
                title: qsTr("Nothing here yet")
                message: app.catalogError || qsTr("New apps will appear here.")
            }
            Repeater {
                model: {
                    const groups = {}
                    for (const e of app.catalog)
                        (groups[e.category || qsTr("Apps")] = groups[e.category || qsTr("Apps")] || []).push(e)
                    return Object.keys(groups).sort().map(k => ({ title: k, apps: groups[k] }))
                }
                delegate: ListGroup {
                    required property var modelData
                    title: modelData.title
                    Repeater {
                        model: modelData.apps
                        delegate: AppRow { required property var modelData; required property int index; entry: modelData }
                    }
                }
            }
            ListGroup {
                visible: app.localFiles.length > 0
                title: qsTr("From your Downloads")
                footer: qsTr("Only install files from people you trust.")
                Repeater {
                    model: app.localFiles
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        subtitle: (modelData.size / 1048576).toFixed(1) + " MB"
                        iconName: "download"
                        separator: index < app.localFiles.length - 1
                        onClicked: System.call("packages.install", { path: modelData.path }, function(r, err) {
                            Dialogs.show({ title: err ? qsTr("Couldn't install the app") : qsTr("App installed"), message: err || modelData.name,
                                           icon: err ? "warning" : "check-circle", buttons: [ { id: "ok", label: qsTr("OK") } ] })
                        })
                    }
                }
            }
        }
    }

    // ---- Installed ----------------------------------------------------------------------
    Component {
        id: installedPage
        Page {
            title: qsTr("Installed")
            readonly property var user: app.installed.filter(p => !p.system)
            readonly property var system: app.installed.filter(p => p.system)
            EmptyState { visible: parent.user.length === 0; iconName: "grid"; title: qsTr("No apps from Market yet") }
            ListGroup {
                visible: parent.user.length > 0
                title: qsTr("Your apps")
                Repeater {
                    model: parent.parent.user
                    delegate: ListItem {
                        required property var modelData
                        text: modelData.name
                        subtitle: modelData.version
                        iconSource: modelData.iconUrl
                        Button {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 104; implicitHeight: 32
                            destructive: true
                            text: qsTr("Uninstall")
                            onClicked: Dialogs.show({ title: qsTr("Uninstall %1?").arg(modelData.name), icon: "trash",
                                                      message: qsTr("The app and all of its data will be removed from this phone."),
                                                      buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "u", label: qsTr("Uninstall"), style: "destructive" } ] },
                                                    function(b) { if (b === "u") Packages.uninstall(modelData.package) })
                        }
                    }
                }
            }
            ListGroup {
                title: qsTr("Built into astraOS")
                Repeater {
                    model: parent.parent.system
                    delegate: ListItem {
                        required property var modelData
                        text: modelData.name
                        subtitle: modelData.version
                        iconSource: modelData.iconUrl
                    }
                }
            }
        }
    }

    // ---- tabs -------------------------------------------------------------------------------
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 30
        width: 236
        height: 54
        radius: 27
        color: Theme.surfaceRaised
        Rectangle {
            y: 5; height: 44; width: 110; radius: 22
            color: Theme.surfacePressed
            x: app.tab === "discover" ? 5 : parent.width - width - 5
            Behavior on x { SpringNumberAnimation { preset: Motion.bouncy } }
        }
        Row {
            anchors.fill: parent
            anchors.margins: 5
            Repeater {
                model: [ { id: "discover", label: qsTr("Discover") }, { id: "installed", label: qsTr("Installed") } ]
                delegate: Item {
                    required property var modelData
                    width: 113; height: 44
                    Text { anchors.centerIn: parent; text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1
                           font.weight: Font.DemiBold; color: app.tab === modelData.id ? Theme.accent : Theme.text }
                    MouseArea { anchors.fill: parent; onClicked: app.tab = modelData.id }
                }
            }
        }
    }
}
