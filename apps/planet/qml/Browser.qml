// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core
import Astra.Controls
import Astra.Animation

// Planet, the astraOS web browser.
//  - address bar at the bottom (swipe it sideways to change tab), toolbar
//    that shrinks while you scroll down
//  - tabs overview, private tabs, Favorites / Frequently Visited start page
//  - aA menu: text size, Reader, desktop website, find on page, translate,
//    bookmarks, Reading List, hide toolbar
//  - Bookmarks, Reading List, History and Downloads in the library
//  - Google by default (Settings: DuckDuckGo, Bing, Ecosia, Startpage)
// Launch arguments: { url } { query } { action: "open"|"share", files, text }
Rectangle {
    id: app
    color: Theme.background

    // ---- state -----------------------------------------------------------------
    readonly property string storePath: Files.appData + "/planet.json"
    property var bookmarks: []          // [{ url, title, icon }]
    property var readingList: []        // [{ url, title, added, read }]
    property var history: []            // [{ url, title, time, visits }] newest first
    property var downloads: []          // [{ name, path, url, received, total, state }]
    property string engine: "google"
    property bool blockPopups: true
    property bool javascript: true
    property bool fullScreen: false
    property bool toolbarHidden: false
    property bool showTabs: false
    property bool privateMode: false   // which tab set the overview shows
    property int current: -1
    property var tabs: []               // BrowserTab items
    property int storageGeneration: 0   // bumped to start with no cookies

    readonly property BrowserTab tab: current >= 0 && current < tabs.length ? tabs[current] : null
    readonly property var frequent: {
        const byHost = {}
        for (const h of history) {
            const k = host(h.url)
            if (!byHost[k])
                byHost[k] = { url: h.url, title: h.title, visits: 0 }
            byHost[k].visits += h.visits || 1
        }
        return Object.values(byHost).sort((a, b) => b.visits - a.visits).slice(0, 8)
    }

    readonly property var engines: ({
        google: { name: "Google", search: "https://www.google.com/search?q=", suggest: "https://suggestqueries.google.com/complete/search?client=firefox&q=" },
        duckduckgo: { name: "DuckDuckGo", search: "https://duckduckgo.com/?q=", suggest: "https://duckduckgo.com/ac/?type=list&q=" },
        bing: { name: "Bing", search: "https://www.bing.com/search?q=", suggest: "https://api.bing.com/osjson.aspx?query=" },
        ecosia: { name: "Ecosia", search: "https://www.ecosia.org/search?q=", suggest: "https://ac.ecosia.org/autocomplete?type=list&q=" },
        startpage: { name: "Startpage", search: "https://www.startpage.com/do/search?q=", suggest: "" }
    })

    function host(u) {
        const m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(u || "")
        return m ? m[1].replace(/^www\./, "") : (u || "")
    }
    function toUrl(text) {
        const t = text.trim()
        if (/^(https?|file|about|data):/i.test(t))
            return t
        if (/^[^\s]+\.[a-z]{2,}(:\d+)?(\/.*)?$/i.test(t) || /^localhost(:\d+)?(\/.*)?$/.test(t))
            return "https://" + t
        return engines[engine].search + encodeURIComponent(t)
    }

    function save() { saveTimer.restart() }
    Timer {
        id: saveTimer
        interval: 600
        onTriggered: Files.writeText(app.storePath, JSON.stringify({
            bookmarks: app.bookmarks, readingList: app.readingList, history: app.history.slice(0, 600),
            engine: app.engine, storageGeneration: app.storageGeneration, blockPopups: app.blockPopups, javascript: app.javascript,
            tabs: app.tabs.filter(t => !t.isPrivate && t.url).map(t => ({ url: t.url, desktop: t.desktop })),
            current: app.tab && !app.tab.isPrivate ? app.tabs.filter(t => !t.isPrivate).indexOf(app.tab) : 0
        }))
    }
    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) {}
        bookmarks = s.bookmarks || []
        readingList = s.readingList || []
        history = s.history || []
        engine = engines[s.engine] ? s.engine : "google"
        storageGeneration = s.storageGeneration || 0
        blockPopups = s.blockPopups !== false
        javascript = s.javascript !== false
        for (const t of (s.tabs || []))
            newTab(t.url, false, false).desktop = !!t.desktop
        if (tabs.length === 0)
            newTab("", false, false)
        current = Math.max(0, Math.min(tabs.length - 1, s.current || 0))
        currentChanged()
    }

    // QML has no cookie store: website data lives in a storage folder per
    // generation, so clearing it means moving to a new, empty one.
    function clearCookies() {
        const old = profile.persistentStoragePath
        storageGeneration++
        Files.remove([old])
        for (const t of tabs)
            if (t.started && !t.isPrivate) t.view.reload()
        save()
    }

    function addHistory(url, title) {
        if (!url || url.startsWith("about:") || url.startsWith("data:"))
            return
        const old = history.find(h => h.url === url)
        const entry = { url: url, title: title || (old ? old.title : ""), time: Date.now(), visits: (old ? old.visits : 0) + (old && title ? 0 : 1) }
        history = [entry].concat(history.filter(h => h.url !== url)).slice(0, 600)
        save()
    }
    function isBookmarked(url) { return bookmarks.some(b => b.url === url) }
    function toggleBookmark() {
        if (!tab || !tab.url)
            return
        if (isBookmarked(tab.url))
            bookmarks = bookmarks.filter(b => b.url !== tab.url)
        else
            bookmarks = bookmarks.concat([{ url: tab.url, title: tab.title, icon: tab.icon.toString() }])
        save()
    }
    function addToReadingList(url, title) {
        if (!url || readingList.some(r => r.url === url))
            return
        readingList = [{ url: url, title: title || host(url), added: Date.now(), read: false }].concat(readingList)
        save()
        toast.show(qsTr("Added to Reading List"))
    }

    // ---- tabs ----------------------------------------------------------------
    Component { id: tabComponent; BrowserTab { browser: app } }
    function newTab(url, isPrivate, select) {
        const t = tabComponent.createObject(viewport, { initialUrl: url || "", isPrivate: !!isPrivate, visible: false })
        t.anchors.fill = viewport
        t.contextMenu.connect((req) => contextSheet.show(req))
        tabs = tabs.concat([t])
        if (select !== false)
            current = tabs.length - 1
        save()
        return t
    }
    function closeTab(t) {
        const i = tabs.indexOf(t)
        if (i < 0)
            return
        const list = tabs.slice()
        list.splice(i, 1)
        tabs = list
        t.destroy()
        if (tabs.filter(x => !x.isPrivate).length === 0 && !privateMode)
            newTab("", false, false)
        const same = tabs.filter(x => x.isPrivate === privateMode)
        current = same.length ? tabs.indexOf(same[Math.min(same.length - 1, Math.max(0, i - 1))]) : (tabs.length ? 0 : -1)
        save()
    }
    function open(url) {
        if (!tab)
            newTab("", privateMode)
        tab.load(toUrl(url))
        editing = false
        showTabs = false
    }
    onCurrentChanged: {
        for (let i = 0; i < tabs.length; i++)
            tabs[i].visible = i === current
        if (tab) {
            profile.httpUserAgent = tab.desktop ? desktopAgent : mobileAgent
            privateMode = tab.isPrivate
        }
        findBar.visible = false
        reader.close()
    }

    // ---- web profiles ----------------------------------------------------------
    property string mobileAgent: ""
    property string desktopAgent: ""
    WebEngineProfile {
        id: profile
        storageName: "planet-" + app.storageGeneration
        offTheRecord: false
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
        httpCacheType: WebEngineProfile.DiskHttpCache
        downloadPath: Files.home + "/Download"
        onDownloadRequested: (download) => app.startDownload(download)
        Component.onCompleted: {
            app.desktopAgent = httpUserAgent.replace(/QtWebEngine\/[\d.]+ /, "")
            app.mobileAgent = app.desktopAgent.replace(/\(X11; Linux [^)]*\)/, "(Linux; Android 14; astraOS)").replace("Safari/", "Mobile Safari/")
            httpUserAgent = app.mobileAgent
        }
    }
    WebEngineProfile {
        id: privateProfileItem
        offTheRecord: true
        httpUserAgent: app.mobileAgent
        downloadPath: Files.home + "/Download"
        onDownloadRequested: (download) => app.startDownload(download)
    }
    readonly property alias profile: profile
    readonly property alias privateProfile: privateProfileItem

    function startDownload(d) {
        d.downloadDirectory = Files.home + "/Download"
        d.accept()
        const entry = { name: d.downloadFileName, path: d.downloadDirectory + "/" + d.downloadFileName, url: d.url.toString(), item: d }
        downloads = [entry].concat(downloads)
        toast.show(qsTr("Downloading “%1”").arg(d.downloadFileName))
        d.isFinishedChanged.connect(function() {
            if (d.isFinished && d.state === WebEngineDownloadRequest.DownloadCompleted)
                toast.show(qsTr("“%1” is in Downloads").arg(d.downloadFileName))
            app.downloads = app.downloads.slice()
        })
    }

    // Camera, microphone and location for websites need the app's own
    // permission first (asked once, by the system), then the user's OK for
    // this website.
    function askPermission(permission) {
        const types = {}
        types[WebEnginePermission.PermissionType.Geolocation] = ["astra.permission.LOCATION", qsTr("use your location")]
        types[WebEnginePermission.PermissionType.MediaAudioCapture] = ["astra.permission.MICROPHONE", qsTr("use the microphone")]
        types[WebEnginePermission.PermissionType.MediaVideoCapture] = ["astra.permission.CAMERA", qsTr("use the camera")]
        types[WebEnginePermission.PermissionType.MediaAudioVideoCapture] = ["astra.permission.CAMERA", qsTr("use the camera and microphone")]
        types[WebEnginePermission.PermissionType.Notifications] = ["", qsTr("send notifications")]
        const t = types[permission.permissionType]
        if (!t) {
            permission.deny()
            return
        }
        const ask = function() {
            Dialogs.show({ title: qsTr("“%1” would like to %2").arg(host(permission.origin.toString())).arg(t[1]),
                           buttons: [{ id: "deny", label: qsTr("Don't Allow") }, { id: "allow", label: qsTr("Allow") }] },
                         function(answer) { answer === "allow" ? permission.grant() : permission.deny() })
        }
        if (!t[0])
            return ask()
        Permissions.request(t[0], function(granted) { granted ? ask() : permission.deny() })
    }

    // ---- find on page ------------------------------------------------------------
    property int findCount: 0
    property int findIndex: 0
    function findResult(count, active) { findCount = count; findIndex = active }

    // ---- launch arguments --------------------------------------------------------
    function handleArgs(args) {
        if (!args)
            return
        let u = args.url || ""
        if (!u && args.files && args.files.length)
            u = "file://" + args.files[0]
        if (!u && args.text)
            u = args.text
        if (u) {
            if (tab && !tab.started) tab.load(toUrl(u))
            else newTab(toUrl(u), false)
        } else if (args.query) {
            if (tab && !tab.started) tab.load(toUrl(args.query))
            else newTab(toUrl(args.query), false)
        } else if (args.mode) {
            editing = true
        }
    }
    Component.onCompleted: {
        load()
        handleArgs(Application.args)
    }
    Connections {
        target: Application
        function onIntent(args) { app.handleArgs(args) }
    }

    // ---- page ----------------------------------------------------------------------
    Item {
        id: viewport
        anchors.top: parent.top
        anchors.topMargin: app.fullScreen ? 0 : Theme.statusBarHeight
        width: parent.width
        anchors.bottom: parent.bottom
        anchors.bottomMargin: app.fullScreen || app.toolbarHidden ? 0 : bar.height
    }
    // Status bar backdrop
    Rectangle {
        visible: !app.fullScreen
        width: parent.width
        height: Theme.statusBarHeight
        color: app.tab && app.tab.isPrivate ? "#1C1C22" : Theme.background
    }
    Rectangle {
        // load progress
        visible: app.tab && app.tab.loading
        y: Theme.statusBarHeight
        height: 2.5
        width: parent.width * (app.tab ? app.tab.progress : 0)
        color: Theme.accent
        Behavior on width { NumberAnimation { duration: 140 } }
    }

    ReaderView {
        id: reader
        anchors.fill: viewport
        z: 5
        onUnavailable: toast.show(qsTr("Reader isn't available for this page"))
    }

    // ---- bottom bar ------------------------------------------------------------------
    property bool editing: false
    property real lastScroll: 0
    property bool compact: false
    Connections {
        target: app.tab
        function onScrollYChanged() {
            const y = app.tab.scrollY
            if (y > app.lastScroll + 24 && y > 80) { app.compact = true; app.lastScroll = y }
            else if (y < app.lastScroll - 24 || y < 40) { app.compact = false; app.lastScroll = y }
        }
        function onUrlChanged() { app.compact = false; app.lastScroll = 0 }
    }

    Rectangle {
        id: bar
        visible: !app.fullScreen && !app.toolbarHidden
        anchors.bottom: parent.bottom
        width: parent.width
        height: (app.compact ? 40 : 108) + Theme.homeIndicatorHeight * 0.6
        Behavior on height { SpringNumberAnimation { preset: Motion.snappy } }
        color: app.tab && app.tab.isPrivate ? "#1C1C22" : Theme.glassPanel
        z: 10
        Rectangle { width: parent.width; height: 1; color: Theme.separator; opacity: 0.6 }

        // Address pill
        Rectangle {
            id: pill
            x: 14
            y: app.compact ? 4 : 10
            width: parent.width - 28
            height: app.compact ? 30 : 46
            radius: height / 2
            color: app.compact ? "transparent" : (app.tab && app.tab.isPrivate ? "#3A3A42" : Theme.surfaceRaised)
            Behavior on height { SpringNumberAnimation { preset: Motion.snappy } }

            Text {
                id: aa
                visible: !app.compact
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "a<font size=\"5\">A</font>"
                textFormat: Text.StyledText
                font.family: Theme.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: Theme.text
                MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: pageMenu.open() }
            }
            Text {
                id: addressText
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: lockIcon.visible ? 10 : 0
                width: Math.min(implicitWidth, pill.width - 130)
                elide: Text.ElideRight
                text: !app.tab || !app.tab.started ? qsTr("Search or enter website") : app.host(app.tab.url)
                font.family: Theme.fontFamily
                font.pixelSize: app.compact ? 13 : Theme.bodySize
                color: !app.tab || !app.tab.started ? Theme.textSecondary : Theme.text
            }
            Icon {
                id: lockIcon
                visible: app.tab && app.tab.secure
                anchors.right: addressText.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: app.compact ? 12 : 15
                color: Theme.textSecondary
            }
            Icon {
                visible: !app.compact && app.tab && app.tab.started
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                name: app.tab && app.tab.loading ? "close" : "refresh"
                size: 20
                color: Theme.text
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -12
                    onClicked: app.tab.loading ? app.tab.view.stop() : app.tab.view.reload()
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: app.compact ? 0 : 48
                anchors.rightMargin: app.compact ? 0 : 48
                property real startX
                property bool swiped: false
                onPressed: (m) => { startX = m.x; swiped = false }
                onPositionChanged: (m) => {
                    if (swiped || Math.abs(m.x - startX) < 70)
                        return
                    swiped = true
                    const same = app.tabs.filter(t => t.isPrivate === app.privateMode)
                    const i = same.indexOf(app.tab) + (m.x < startX ? 1 : -1)
                    if (i >= 0 && i < same.length)
                        app.current = app.tabs.indexOf(same[i])
                    else if (i === same.length)
                        app.newTab("", app.privateMode)
                }
                onClicked: {
                    if (swiped)
                        return
                    if (app.compact)
                        app.compact = false
                    else
                        app.editing = true
                }
            }
        }

        // Toolbar
        Item {
            id: toolbar
            visible: !app.compact
            x: 10
            y: 62
            width: bar.width - 20
            height: 40
            readonly property real slot: width / 5
            Tool { x: 0; iconName: "chevron-left"; active: !!app.tab && app.tab.view.canGoBack; onClicked: app.tab.view.goBack() }
            Tool { x: toolbar.slot; iconName: "chevron-right"; active: !!app.tab && app.tab.view.canGoForward; onClicked: app.tab.view.goForward() }
            Tool { x: toolbar.slot * 2; iconName: "share"; active: !!app.tab && app.tab.started; onClicked: share.open([], "text/uri-list", "share", app.tab.url) }
            Tool { x: toolbar.slot * 3; iconName: "book"; onClicked: library.open() }
            Tool { x: toolbar.slot * 4; iconName: "tabs"; onClicked: app.openTabs(); onHeld: tabMenu.open() }
        }
    }

    component Tool: Item {
        id: tool
        property string iconName
        property bool active: true
        signal clicked()
        signal held()
        width: toolbar.slot
        height: 40
        Icon {
            anchors.centerIn: parent
            name: tool.iconName
            size: 24
            color: Theme.accent
            opacity: tool.active ? (toolArea.pressed ? 0.5 : 1) : 0.3
        }
        MouseArea {
            id: toolArea
            anchors.fill: parent
            enabled: tool.active
            onClicked: tool.clicked()
            onPressAndHold: tool.held()
        }
    }

    // ---- address editing ---------------------------------------------------------------
    AddressEditor {
        id: editor
        anchors.fill: parent
        browser: app
        z: 30
        active: app.editing
        onDone: app.editing = false
    }

    // ---- find on page --------------------------------------------------------------------
    Rectangle {
        id: findBar
        visible: false
        z: 20
        anchors.bottom: parent.bottom
        width: parent.width
        height: 60 + Theme.homeIndicatorHeight * 0.6
        color: Theme.glassPanel
        onVisibleChanged: {
            if (visible) { findInput.text = ""; findInput.forceActiveFocus() }
            else if (app.tab) app.tab.view.findText("")
        }
        Row {
            x: 12
            y: 8
            spacing: 8
            Rectangle {
                width: findBar.width - 24 - 3 * 44 - 3 * 8
                height: 44
                radius: 22
                color: Theme.surfaceRaised
                TextInput {
                    id: findInput
                    anchors.fill: parent
                    anchors.leftMargin: 18
                    anchors.rightMargin: 70
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.text
                    inputMethodHints: Qt.ImhNoPredictiveText
                    onTextChanged: if (app.tab) app.tab.view.findText(text)
                    onAccepted: if (app.tab) app.tab.view.findText(text)
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: findInput.text !== ""
                    text: app.findCount ? qsTr("%1 of %2").arg(app.findIndex).arg(app.findCount) : qsTr("No matches")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize
                    color: Theme.textSecondary
                }
            }
            IconButton { iconName: "chevron-up"; onClicked: app.tab.view.findText(findInput.text, WebEngineView.FindBackward) }
            IconButton { iconName: "chevron-down"; onClicked: app.tab.view.findText(findInput.text) }
            IconButton { iconName: "check"; color: Theme.accent; onClicked: findBar.visible = false }
        }
    }

    // ---- tabs overview -------------------------------------------------------------------
    function openTabs() {
        if (!tab) {
            showTabs = true
            return
        }
        tab.snapshot(function() { app.showTabs = true })
    }
    TabsView {
        id: tabsView
        anchors.fill: parent
        z: 25
        browser: app
        shown: app.showTabs
    }

    // ---- sheets ------------------------------------------------------------------------------
    Sheet {
        id: tabMenu
        Column {
            width: parent.width
            ListGroup {
                ListItem { text: qsTr("New Tab"); iconName: "plus"; onClicked: { tabMenu.close(); app.newTab("", false); app.editing = true } }
                ListItem { text: qsTr("New Private Tab"); iconName: "eye-off"; onClicked: { tabMenu.close(); app.newTab("", true); app.editing = true } }
                ListItem { text: qsTr("Close This Tab"); iconName: "close"; destructive: true; separator: false; enabled: app.tab !== null; onClicked: { tabMenu.close(); app.closeTab(app.tab) } }
            }
        }
    }

    Sheet {
        id: pageMenu
        Column {
            width: parent.width
            spacing: 14
            Rectangle {
                width: parent.width
                height: 54
                radius: Theme.radius
                color: Theme.surface
                Row {
                    anchors.fill: parent
                    Item {
                        width: parent.width / 3; height: parent.height
                        Text { anchors.centerIn: parent; text: "A"; font.family: Theme.fontFamily; font.pixelSize: 14; color: Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: if (app.tab) app.tab.textZoom = Math.max(0.5, Math.round((app.tab.textZoom - 0.1) * 10) / 10) }
                    }
                    Item {
                        width: parent.width / 3; height: parent.height
                        Text { anchors.centerIn: parent; text: Math.round((app.tab ? app.tab.textZoom : 1) * 100) + "%"; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: if (app.tab) app.tab.textZoom = 1 }
                    }
                    Item {
                        width: parent.width / 3; height: parent.height
                        Text { anchors.centerIn: parent; text: "A"; font.family: Theme.fontFamily; font.pixelSize: 22; color: Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: if (app.tab) app.tab.textZoom = Math.min(3, Math.round((app.tab.textZoom + 0.1) * 10) / 10) }
                    }
                }
            }
            ListGroup {
                ListItem {
                    text: qsTr("Show Reader")
                    iconName: "book"
                    enabled: app.tab && app.tab.started
                    onClicked: { pageMenu.close(); reader.show(app.tab.view) }
                }
                ListItem {
                    text: app.tab && app.tab.desktop ? qsTr("Request Mobile Website") : qsTr("Request Desktop Website")
                    iconName: "desktop"
                    enabled: app.tab && app.tab.started
                    onClicked: {
                        pageMenu.close()
                        app.tab.desktop = !app.tab.desktop
                        app.profile.httpUserAgent = app.tab.desktop ? app.desktopAgent : app.mobileAgent
                        app.tab.view.reload()
                        app.save()
                    }
                }
                ListItem {
                    text: qsTr("Find on Page")
                    iconName: "search"
                    enabled: app.tab && app.tab.started
                    onClicked: { pageMenu.close(); findBar.visible = true }
                }
                ListItem {
                    text: qsTr("Translate")
                    iconName: "language"
                    enabled: app.tab && app.tab.started && !app.tab.url.startsWith("file:")
                    onClicked: {
                        pageMenu.close()
                        app.tab.load("https://translate.google.com/translate?sl=auto&tl=" + Language.current + "&u=" + encodeURIComponent(app.tab.url))
                    }
                }
                ListItem {
                    text: qsTr("Hide Toolbar")
                    iconName: "arrow-up"
                    separator: false
                    onClicked: { pageMenu.close(); app.toolbarHidden = true }
                }
            }
            ListGroup {
                ListItem {
                    text: app.tab && app.isBookmarked(app.tab.url) ? qsTr("Remove Bookmark") : qsTr("Add Bookmark")
                    iconName: "bookmark"
                    enabled: app.tab && app.tab.started && !app.tab.isPrivate
                    onClicked: { pageMenu.close(); app.toggleBookmark() }
                }
                ListItem {
                    text: qsTr("Add to Reading List")
                    iconName: "book"
                    enabled: app.tab && app.tab.started
                    separator: false
                    onClicked: { pageMenu.close(); app.addToReadingList(app.tab.url, app.tab.title) }
                }
            }
        }
    }
    // Hidden toolbar: a tap at the bottom brings it back.
    MouseArea {
        visible: app.toolbarHidden && !app.fullScreen
        anchors.bottom: parent.bottom
        width: parent.width
        height: 34
        z: 11
        onClicked: app.toolbarHidden = false
    }

    Library {
        id: library
        browser: app
    }

    ShareSheet {
        id: share
        anchors.fill: parent
        z: 60
    }

    Sheet {
        id: contextSheet
        property var request: null
        property string link: ""
        property string media: ""
        function show(req) {
            request = req
            link = req.linkUrl.toString()
            media = req.mediaType === ContextMenuRequest.MediaTypeImage ? req.mediaUrl.toString() : ""
            if (!link && !media) {
                if (req.isContentEditable || req.selectedText) {
                    // Text selection: copy
                    if (req.selectedText)
                        app.tab.view.triggerWebAction(WebEngineView.Copy)
                    return
                }
                return
            }
            open()
        }
        title: link ? app.host(link) : qsTr("Image")
        Column {
            width: parent.width
            ListGroup {
                ListItem { visible: contextSheet.link !== ""; text: qsTr("Open in New Tab"); iconName: "plus"; onClicked: { contextSheet.close(); app.newTab(contextSheet.link, app.privateMode, false); toast.show(qsTr("Opened in a new tab")) } }
                ListItem { visible: contextSheet.link !== ""; text: qsTr("Open in Private Tab"); iconName: "eye-off"; onClicked: { contextSheet.close(); app.newTab(contextSheet.link, true) } }
                ListItem { visible: contextSheet.link !== ""; text: qsTr("Add to Reading List"); iconName: "book"; onClicked: { contextSheet.close(); app.addToReadingList(contextSheet.link, contextSheet.request.linkText) } }
                ListItem { visible: contextSheet.link !== ""; text: qsTr("Copy Link"); iconName: "copy"; onClicked: { contextSheet.close(); app.tab.view.triggerWebAction(WebEngineView.CopyLinkToClipboard) } }
                ListItem { visible: contextSheet.link !== ""; text: qsTr("Download Linked File"); iconName: "download"; onClicked: { contextSheet.close(); app.tab.view.triggerWebAction(WebEngineView.DownloadLinkToDisk) } }
                ListItem { visible: contextSheet.media !== ""; text: qsTr("Save Image"); iconName: "image"; onClicked: { contextSheet.close(); app.tab.view.triggerWebAction(WebEngineView.DownloadImageToDisk) } }
                ListItem { visible: contextSheet.media !== ""; text: qsTr("Copy Image"); iconName: "copy"; onClicked: { contextSheet.close(); app.tab.view.triggerWebAction(WebEngineView.CopyImageToClipboard) } }
                ListItem { visible: contextSheet.link !== "" || contextSheet.media !== ""; text: qsTr("Share"); iconName: "share"; separator: false; onClicked: { contextSheet.close(); share.open([], "text/uri-list", "share", contextSheet.link || contextSheet.media) } }
            }
        }
    }

    // ---- toast ------------------------------------------------------------------------------
    Rectangle {
        id: toast
        z: 90
        function show(text) { toastText.text = text; opacity = 1; toastTimer.restart() }
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - bar.height - height - 16
        width: toastText.implicitWidth + 36
        height: 40
        radius: 20
        color: Theme.light ? "#1C1C22" : "#3A3A42"
        Text { id: toastText; anchors.centerIn: parent; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: "white" }
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.opacity = 0 }
    }
}
