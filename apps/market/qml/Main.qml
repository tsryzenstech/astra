// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation
import "Server.js" as Server

// Market: the astraOS app store. Today (stories, App and Game of the Day,
// charts), Apps by category, Search and Updates. The catalog comes from the
// astra cloud server in config.json (Server.js is generated from it when the
// package is built), or from Settings key "market.server" when set.
Rectangle {
    id: app
    color: Theme.background

    readonly property string server: (Settings.values["market.server"] || Server.url).replace(/\/$/, "")
    property var catalog: []                 // [{ package, name, summary, category, version, versionCode, size, sha256, url, icon }]
    property var today: null                 // /api/store/today
    property string error: ""
    property bool loading: false
    property var installing: ({})            // package -> true
    property string tab: "today"             // today | apps | search | updates
    readonly property var installed: Packages.count >= 0 ? Packages.list() : []
    readonly property var updates: catalog.filter(e => { const v = installedVersion(e.package); return v > 0 && (e.versionCode || 1) > v })

    // Settings arrive a moment after start: reload when the address changes.
    onServerChanged: load()

    function installedVersion(pkg) {
        const p = installed.find(i => i.package === pkg)
        return p ? (p.versionCode || 1) : 0
    }
    function size(b) { return b >= 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1e3)) + " KB" }

    function get(path, done) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) { done(null, xhr.status); return }
            try { done(JSON.parse(xhr.responseText), 200) } catch (e) { done(null, -1) }
        }
        xhr.open("GET", server + path)
        xhr.send()
    }
    function load() {
        loading = true
        get("/api/store/index.json", function(list, status) {
            app.loading = false
            if (!list) { app.error = status === 0 ? qsTr("Market can't be reached. Check your connection.") : qsTr("Market is not available right now."); return }
            app.error = ""
            app.catalog = list
        })
        get("/api/store/today", function(t) { if (t) app.today = t })
    }
    function install(entry) {
        if (installing[entry.package]) return
        const busy = Object.assign({}, installing)
        busy[entry.package] = true
        installing = busy
        System.call("packages.installUrl", { url: entry.url, sha256: entry.sha256 || "" }, function(r, err) {
            const b = Object.assign({}, app.installing)
            delete b[entry.package]
            app.installing = b
            if (err)
                Dialogs.show({ title: qsTr("Couldn't install %1").arg(entry.name), message: err, icon: "warning",
                               buttons: [{ id: "ok", label: qsTr("OK") }] })
        })
    }
    function updateAll() { for (const e of updates) install(e) }
    function openPage(entry) { stack.open(Qt.resolvedUrl("AppPage.qml"), { store: app, entry: entry }) }
    function openStory(story) { stack.open(Qt.resolvedUrl("StoryPage.qml"), { store: app, story: story }) }

    // An .apkg opened from Files or the browser: only with Sideload Apps on.
    function installShared(args) {
        if (!args || !args.files || !args.files.length) return
        const path = args.files[0]
        System.call("packages.canSideload", {}, function(allowed) {
            if (!allowed) {
                Dialogs.show({ title: qsTr("Sideloading is off"),
                               message: qsTr("Apps can be installed only from Market. To install files, turn on Sideload Apps in Settings › Developer Options."),
                               icon: "shield", buttons: [{ id: "ok", label: qsTr("OK") }, { id: "settings", label: qsTr("Settings") }] },
                             function(b) { if (b === "settings") Packages.launch("com.astra.settings", { page: "developer" }) })
                return
            }
            Dialogs.show({ title: qsTr("Install this app?"), message: path.split("/").pop() + "\n" + qsTr("Only install files from people you trust."),
                           icon: "download", buttons: [{ id: "c", label: qsTr("Cancel") }, { id: "i", label: qsTr("Install"), style: "primary" }] },
                         function(b) {
                             if (b !== "i") return
                             System.call("packages.install", { path: path }, function(r, err) {
                                 Dialogs.show({ title: err ? qsTr("Couldn't install the app") : qsTr("App installed"), message: err || "",
                                                icon: err ? "warning" : "check-circle", buttons: [{ id: "ok", label: qsTr("OK") }] })
                             })
                         })
        })
    }

    Component.onCompleted: {
        load()
        installShared(Application.args)
        if (Application.args.package)
            showPackage.target = Application.args.package
    }
    Connections {
        target: Application
        function onIntent(args) {
            app.installShared(args)
            if (args.package) showPackage.target = args.package
        }
    }
    // Deep link { package }: open the app page once the catalog is there.
    QtObject {
        id: showPackage
        property string target: ""
        onTargetChanged: tryOpen()
        function tryOpen() {
            const e = app.catalog.find(x => x.package === target)
            if (e) { app.openPage(e); target = "" }
        }
    }
    onCatalogChanged: if (showPackage.target) showPackage.tryOpen()

    PageStack {
        id: stack
        anchors.fill: parent
        anchors.bottomMargin: tabs.height
        initialItem: Component {
            Item {
                TodayPage { anchors.fill: parent; store: app; visible: app.tab === "today" }
                AppsPage { anchors.fill: parent; store: app; visible: app.tab === "apps" }
                SearchPage { anchors.fill: parent; store: app; visible: app.tab === "search" }
                UpdatesPage { anchors.fill: parent; store: app; visible: app.tab === "updates" }
            }
        }
    }

    // ---- tab bar -----------------------------------------------------------
    Rectangle {
        id: tabs
        anchors.bottom: parent.bottom
        width: parent.width
        height: 58 + Theme.homeIndicatorHeight * 0.6
        color: Theme.glassPanel
        Rectangle { width: parent.width; height: 1; color: Theme.separator }
        Row {
            y: 6
            Repeater {
                model: [
                    { id: "today", icon: "sparkles", label: qsTr("Today") },
                    { id: "apps", icon: "grid", label: qsTr("Apps") },
                    { id: "search", icon: "search", label: qsTr("Search") },
                    { id: "updates", icon: "download", label: qsTr("Updates") }
                ]
                delegate: Item {
                    required property var modelData
                    readonly property bool on: app.tab === modelData.id
                    width: tabs.width / 4
                    height: 48
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; y: 2; name: parent.modelData.icon; size: 24; color: parent.on ? Theme.accent : Theme.textSecondary }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; y: 30; text: parent.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 11; color: parent.on ? Theme.accent : Theme.textSecondary }
                    Rectangle {
                        visible: parent.modelData.id === "updates" && app.updates.length > 0
                        x: parent.width / 2 + 6; y: 0
                        width: 18; height: 18; radius: 9
                        color: Theme.danger
                        Text { anchors.centerIn: parent; text: app.updates.length; font.family: Theme.fontFamily; font.pixelSize: 11; font.weight: Font.Bold; color: "white" }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { app.tab = parent.modelData.id; if (stack.depth > 1) stack.pop(null) }
                    }
                }
            }
        }
    }
}
