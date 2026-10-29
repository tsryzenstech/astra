// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The home screen (HomeConfig1.png). Part of SysBoard: it cannot be
// replaced by apps.
//
// Every page is a 4 column grid packed like iOS: apps and folders take one
// cell, big folders and small widgets 2 x 2, medium widgets 4 x 2, large
// ones 4 x 4, the search bar 4 x 1. Items keep an order per page and the
// grid is packed from it, so moving one only changes orders and every
// displacement animates with a spring. The dock holds up to four apps,
// centred whatever their number.
//
// Saved in "home.layout": { version: 2, pages: [[entry]], dock: [pkg], hidden: [pkg] }
// with entry = "pkg" | { folder: { id, name, apps, big } } | { widget: { key, size } }
Item {
    id: home

    property var shell
    property real appProgress: 0
    property bool interactive: true
    property bool editing: false
    property bool animateLayout: false
    // The package whose window is growing out of (or back into) its icon.
    property string hiddenPackage: ""
    property var appLayer: null
    // 0..1 while the bottom edge is pulled on home: the page shrinks a little.
    property real recentsPull: 0

    // ---- geometry (reference: 393 x 852 logical px) ----------------------
    readonly property real sidePadding: 10
    readonly property real cellWidth: (width - 2 * sidePadding) / 4
    readonly property real iconSize: 62
    readonly property real dockIconSize: 70
    readonly property real rowHeight: 106
    readonly property real dockHeight: 107
    readonly property real dockY: height - 37 - dockHeight
    readonly property real gridTop: 96
    readonly property int rows: Math.max(3, Math.floor((dockY - 59 - gridTop) / rowHeight))
    onRowsChanged: if (items.count) { rebuild() }     // the screen size arrived: pack again from the saved layout
    readonly property real inset: (cellWidth - iconSize) / 2
    property int dockCount: 0

    function sizeOf(kind, wsize, big) {
        if (kind === "widget")
            return ({ small: [2, 2], medium: [4, 2], large: [4, 4], bar: [4, 1] })[wsize] || [2, 2]
        if (kind === "folder" && big)
            return [2, 2]
        return [1, 1]
    }
    function cellX(col) { return sidePadding + cellWidth * col + inset }
    function cellY(row) { return gridTop + rowHeight * row }
    function spanW(w) { return (w - 1) * cellWidth + iconSize }
    function spanH(h) { return h === 1 ? iconSize : (h - 1) * rowHeight + iconSize }
    function dockX(slot) {
        const cell = (width - 20) / 4
        const start = 10 + (width - 20 - cell * Math.max(1, dockCount)) / 2
        return start + cell * slot + (cell - dockIconSize) / 2
    }

    // ---- paging ----------------------------------------------------------
    property int currentPage: 0
    property int pageCount: 1
    readonly property real pageOffset: pager.value
    Spring { id: pager; to: -home.currentPage * home.width; response: 0.36; dampingFraction: 0.9 }
    onWidthChanged: pager.snap(-currentPage * width)
    function goToPage(p, velocity) {
        currentPage = Math.max(0, Math.min(pageCount - 1, p))
        pager.animateTo(-currentPage * width, velocity || 0)
        pageDotsTimer.restart()
    }

    // ---- model -------------------------------------------------------------
    // kind: app | folder | widget; container: page (or -1 dock); order in
    // the page; col/row/w/h from packing.
    ListModel { id: items }
    property var hiddenApps: []
    property int nextFolderId: 1

    function installed() {
        const out = {}
        for (const p of Packages.list())
            if (p.launcher)
                out[p.package] = p
        return out
    }
    function indexOfKey(key) {
        for (let i = 0; i < items.count; ++i)
            if (items.get(i).key === key)
                return i
        return -1
    }
    function indexOf(pkg) { return indexOfKey("app:" + pkg) }
    function folderApps(i) { try { return JSON.parse(items.get(i).apps || "[]") } catch (e) { return [] } }

    function rebuild() {
        if (!Packages.ready || !Settings.ready)
            return
        let layout = Settings.values["home.layout"] || { pages: [[]], dock: [] }
        const apps = installed()
        hiddenApps = (layout.hidden || []).filter(p => apps[p])
        let pages = layout.pages && layout.pages.length ? layout.pages.map(p => p.slice()) : [[]]
        // Layouts from before widgets: the weather and search widgets lead page one.
        if (!layout.version)
            pages[0] = [{ widget: { key: "system/greeting", size: "medium" } }, { widget: { key: "system/search", size: "bar" } }].concat(pages[0])

        const wanted = []
        const placed = {}
        const widgetsAvail = {}
        for (const w of Packages.widgets) widgetsAvail[w.key] = w
        let slot = 0
        for (const pkg of (layout.dock || []))
            if (apps[pkg] && !placed[pkg] && slot < 4) {
                placed[pkg] = true
                wanted.push({ key: "app:" + pkg, kind: "app", pkg: pkg, container: -1, order: slot++ })
            }
        let wid = 0
        for (let page = 0; page < pages.length; ++page) {
            let order = 0
            for (const e of pages[page]) {
                if (typeof e === "string") {
                    if (apps[e] && !placed[e]) {
                        placed[e] = true
                        wanted.push({ key: "app:" + e, kind: "app", pkg: e, container: page, order: order++ })
                    }
                } else if (e && e.folder) {
                    const list = (e.folder.apps || []).filter(p => apps[p] && !placed[p])
                    list.forEach(p => placed[p] = true)
                    if (list.length === 0) continue
                    const id = e.folder.id || nextFolderId++
                    nextFolderId = Math.max(nextFolderId, id + 1)
                    wanted.push({ key: "folder:" + id, kind: "folder", name: e.folder.name || qsTr("Folder"), apps: JSON.stringify(list),
                                  big: !!e.folder.big, container: page, order: order++ })
                } else if (e && e.widget && (e.widget.key.startsWith("system/") || widgetsAvail[e.widget.key])) {
                    wanted.push({ key: "widget:" + (wid++) + ":" + e.widget.key, kind: "widget", wkey: e.widget.key,
                                  wsize: e.widget.size || "small", container: page, order: order++ })
                }
            }
        }
        // New apps go to the end, after the last page.
        const lastPage = Math.max(0, pages.length - 1)
        let tail = wanted.filter(w => w.container === lastPage).length
        for (const pkg of Object.keys(apps).sort())
            if (!placed[pkg] && hiddenApps.indexOf(pkg) < 0)
                wanted.push({ key: "app:" + pkg, kind: "app", pkg: pkg, container: lastPage, order: tail++ })

        // Reconcile in place so existing items animate.
        const keep = {}
        for (const w of wanted) keep[w.key] = true
        for (let i = items.count - 1; i >= 0; --i)
            if (!keep[items.get(i).key])
                items.remove(i)
        for (const w of wanted) {
            const p = w.pkg ? apps[w.pkg] : null
            const data = { key: w.key, kind: w.kind, pkg: w.pkg || "", name: p ? p.name : (w.name || ""), icon: p ? p.iconUrl.toString() : "",
                           system: p ? !!p.system : false, apps: w.apps || "[]", big: !!w.big, wkey: w.wkey || "", wsize: w.wsize || "",
                           container: w.container, order: w.order, col: 0, row: 0, w: 1, h: 1 }
            const i = indexOfKey(w.key)
            if (i < 0) items.append(data)
            else items.set(i, data)
        }
        relayout()
    }

    // Packs every page; items that don't fit move to the next page.
    function relayout() {
        let page = 0
        let maxPage = 0
        for (let i = 0; i < items.count; ++i)
            maxPage = Math.max(maxPage, items.get(i).container)
        dockCount = 0
        for (let i = 0; i < items.count; ++i)
            if (items.get(i).container < 0) {
                dockCount++
                const s = sizeOf(items.get(i).kind, items.get(i).wsize, items.get(i).big)
                items.setProperty(i, "w", s[0]); items.setProperty(i, "h", s[1])
            }
        for (page = 0; page <= maxPage; ++page) {
            const list = []
            for (let i = 0; i < items.count; ++i)
                if (items.get(i).container === page)
                    list.push(i)
            list.sort((a, b) => items.get(a).order - items.get(b).order)
            const grid = []
            for (let r = 0; r < rows; ++r) grid.push([false, false, false, false])
            let order = 0
            for (const i of list) {
                const it = items.get(i)
                const s = sizeOf(it.kind, it.wsize, it.big)
                let spot = null
                for (let r = 0; r + s[1] <= rows && !spot; ++r)
                    for (let c = 0; c + s[0] <= 4 && !spot; c += s[0] === 1 ? 1 : 2) {
                        let free = true
                        for (let dr = 0; dr < s[1] && free; ++dr)
                            for (let dc = 0; dc < s[0] && free; ++dc)
                                if (grid[r + dr][c + dc]) free = false
                        if (free) spot = [r, c]
                    }
                if (!spot) {
                    // Overflow: first on the next page.
                    items.setProperty(i, "container", page + 1)
                    items.setProperty(i, "order", -1 - order)
                    maxPage = Math.max(maxPage, page + 1)
                    continue
                }
                for (let dr = 0; dr < s[1]; ++dr)
                    for (let dc = 0; dc < s[0]; ++dc)
                        grid[spot[0] + dr][spot[1] + dc] = true
                items.setProperty(i, "row", spot[0]); items.setProperty(i, "col", spot[1])
                items.setProperty(i, "w", s[0]); items.setProperty(i, "h", s[1])
                items.setProperty(i, "order", order++)
            }
        }
        // Drop empty pages at the end (never the first) and renumber gaps.
        const used = {}
        for (let i = 0; i < items.count; ++i)
            if (items.get(i).container >= 0) used[items.get(i).container] = true
        const remap = {}
        let next = 0
        for (let p2 = 0; p2 <= maxPage; ++p2)
            if (used[p2] || p2 === 0) remap[p2] = next++
        for (let i = 0; i < items.count; ++i) {
            const c = items.get(i).container
            if (c >= 0 && remap[c] !== undefined && remap[c] !== c)
                items.setProperty(i, "container", remap[c])
        }
        pageCount = Math.max(1, next + (touch.dragging ? 1 : 0))
        if (currentPage >= pageCount)
            goToPage(pageCount - 1)
    }

    function saveLayout() {
        const pages = []
        const dock = []
        const sorted = []
        for (let i = 0; i < items.count; ++i) sorted.push(items.get(i))
        sorted.sort((a, b) => a.container - b.container || a.order - b.order)
        for (const it of sorted) {
            let entry
            if (it.kind === "app") entry = it.pkg
            else if (it.kind === "folder") entry = { folder: { id: Number(it.key.split(":")[1]), name: it.name, apps: JSON.parse(it.apps), big: it.big } }
            else entry = { widget: { key: it.wkey, size: it.wsize } }
            if (it.container < 0) {
                if (it.kind === "app") dock.push(it.pkg)
            } else {
                while (pages.length <= it.container) pages.push([])
                pages[it.container].push(entry)
            }
        }
        Settings.setValue("home.layout", { version: 2, pages: pages, dock: dock, hidden: hiddenApps })
    }

    // Moves item i to (container, before order); shifts the rest.
    function moveTo(i, container, order) {
        const it = items.get(i)
        if (container < 0) {
            if (it.kind !== "app") return false
            if (it.container !== -1 && dockCount >= 4) return false
        }
        for (let j = 0; j < items.count; ++j) {
            if (j === i) continue
            const o = items.get(j)
            if (o.container === it.container && o.order > it.order)
                items.setProperty(j, "order", o.order - 1)
        }
        let max = 0
        for (let j = 0; j < items.count; ++j)
            if (j !== i && items.get(j).container === container) max++
        order = Math.max(0, Math.min(order, max))
        for (let j = 0; j < items.count; ++j) {
            if (j === i) continue
            const o = items.get(j)
            if (o.container === container && o.order >= order)
                items.setProperty(j, "order", o.order + 1)
        }
        items.setProperty(i, "container", container)
        items.setProperty(i, "order", order)
        relayout()
        return true
    }

    // ---- folders, widgets, removal ---------------------------------------------
    function makeFolder(dragIndex, targetIndex) {
        const a = items.get(targetIndex), b = items.get(dragIndex)
        const id = nextFolderId++
        const data = { key: "folder:" + id, kind: "folder", pkg: "", name: suggestName([a.pkg, b.pkg]), icon: "", system: false,
                       apps: JSON.stringify([a.pkg, b.pkg]), big: false, wkey: "", wsize: "", container: a.container, order: a.order,
                       col: a.col, row: a.row, w: 1, h: 1 }
        // The folder takes the target's place.
        const keys = [a.key, b.key]
        items.append(data)
        for (const k of keys) items.remove(indexOfKey(k))
        relayout()
        saveLayout()
    }
    function suggestName(pkgs) {
        const cats = pkgs.map(p => (Packages.get(p) || {}).category || "")
        if (cats.every(c => c === "Games")) return qsTr("Games")
        if (cats.every(c => c === "Social")) return qsTr("Social")
        return qsTr("Folder")
    }
    function addToFolder(dragIndex, folderIndex) {
        const list = folderApps(folderIndex)
        list.push(items.get(dragIndex).pkg)
        items.setProperty(folderIndex, "apps", JSON.stringify(list))
        items.remove(dragIndex)
        relayout()
        saveLayout()
    }
    function removeFromFolder(folderKey, pkg) {
        const fi = indexOfKey(folderKey)
        if (fi < 0) return
        const f = items.get(fi)
        const list = folderApps(fi).filter(p => p !== pkg)
        const apps = installed()
        const p = apps[pkg]
        if (p)
            items.append({ key: "app:" + pkg, kind: "app", pkg: pkg, name: p.name, icon: p.iconUrl.toString(), system: !!p.system,
                           apps: "[]", big: false, wkey: "", wsize: "", container: f.container, order: f.order + 0.5, col: 0, row: 0, w: 1, h: 1 })
        if (list.length <= 1) {
            // One app left: the folder dissolves into it.
            if (list.length === 1 && apps[list[0]])
                items.append({ key: "app:" + list[0], kind: "app", pkg: list[0], name: apps[list[0]].name, icon: apps[list[0]].iconUrl.toString(),
                               system: !!apps[list[0]].system, apps: "[]", big: false, wkey: "", wsize: "", container: f.container, order: f.order,
                               col: 0, row: 0, w: 1, h: 1 })
            items.remove(indexOfKey(folderKey))
            folderView.close()
        } else {
            items.setProperty(fi, "apps", JSON.stringify(list))
        }
        relayout()
        saveLayout()
    }
    function renameFolder(folderKey, name) {
        const fi = indexOfKey(folderKey)
        if (fi >= 0 && name.trim()) { items.setProperty(fi, "name", name.trim()); saveLayout() }
    }
    function setFolderBig(folderKey, big) {
        const fi = indexOfKey(folderKey)
        if (fi >= 0) { items.setProperty(fi, "big", big); relayout(); saveLayout() }
    }
    function removeItem(i) {
        const it = items.get(i)
        if (it.kind === "app") {
            hiddenApps = hiddenApps.concat([it.pkg])        // still in the App Library
            items.remove(i)
        } else if (it.kind === "folder") {
            const list = folderApps(i)
            const apps = installed()
            const base = { container: it.container, order: it.order }
            items.remove(i)
            list.forEach((p, k) => { if (apps[p]) items.append({ key: "app:" + p, kind: "app", pkg: p, name: apps[p].name, icon: apps[p].iconUrl.toString(),
                                     system: !!apps[p].system, apps: "[]", big: false, wkey: "", wsize: "", container: base.container,
                                     order: base.order + k * 0.01, col: 0, row: 0, w: 1, h: 1 }) })
        } else {
            items.remove(i)
        }
        relayout()
        saveLayout()
    }
    function addWidget(key, size) {
        let n = 0
        for (let i = 0; i < items.count; ++i) n = Math.max(n, Number((items.get(i).key.split(":")[1]) || 0) + 1)
        items.append({ key: "widget:" + (n + 100) + ":" + key, kind: "widget", pkg: "", name: "", icon: "", system: false, apps: "[]",
                       big: false, wkey: key, wsize: size, container: currentPage, order: -1, col: 0, row: 0, w: 1, h: 1 })
        relayout()
        saveLayout()
    }
    function showApp(pkg) {
        // From the App Library: back on the home screen.
        hiddenApps = hiddenApps.filter(p => p !== pkg)
        saveLayout()
        rebuild()
    }

    // Screen rect of an app icon, used by app open/close transitions.
    function iconRect(pkg) {
        const i = indexOf(pkg)
        if (i < 0)
            return null
        const it = items.get(i)
        if (it.container >= 0 && it.container !== currentPage)
            return null
        const d = repeater.itemAt(i)
        return d ? d.mapToItem(home, 0, 0, iconSize, iconSize) : null
    }
    function launchApp(pkg, item) {
        shell.launch(pkg, {}, item ? item.mapToItem(home, 0, 0, item.width, item.width) : null)
    }

    // ---- entrance after unlocking: everything drops in from the top ----
    function playEntrance() {
        for (let i = 0; i < repeater.count; ++i) {
            const d = repeater.itemAt(i)
            if (d) d.fall()
        }
    }

    Connections {
        target: Packages
        function onCountChanged() { home.rebuild() }
        function onReadyChanged() { home.rebuild() }
        function onPackageChanged(pkg) { renameTimer.restart() }
    }
    Connections {
        target: Settings
        function onValuesChanged() { if (items.count === 0) home.rebuild() }
    }
    Timer { id: renameTimer; interval: 100; onTriggered: home.rebuild() }
    Component.onCompleted: {
        rebuild()
        Qt.callLater(() => home.animateLayout = true)
    }

    // ---- content -----------------------------------------------------------
    Item {
        id: content
        anchors.fill: parent
        opacity: 1 - home.appProgress
        scale: (1 + 0.08 * home.appProgress) * (1 - 0.1 * home.recentsPull)

        Image {
            anchors.fill: parent
            source: home.shell ? home.shell.wallpaper : Host.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
            scale: 1 / Math.max(0.01, 1 - 0.1 * home.recentsPull)   // the wallpaper stays put
        }

        Rectangle {
            id: dock
            x: 10
            y: home.dockY
            width: home.width - 20          // the dock never shrinks
            height: home.dockHeight
            radius: 42
            color: Qt.rgba(0, 0, 0, 0.28)
        }

        // App Library pill; shows page dots while paging.
        Rectangle {
            id: searchPill
            anchors.horizontalCenter: parent.horizontalCenter
            y: home.dockY - 49
            width: pageDots.visibleDots ? Math.max(74, dotsRow.width + 26) : 74
            height: 30
            radius: 15
            color: Qt.rgba(0, 0, 0, 0.3)
            Behavior on width { SpringNumberAnimation { preset: Motion.snappy } }
            Row {
                anchors.centerIn: parent
                spacing: 5
                opacity: pageDots.visibleDots ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Icon { name: "search"; size: 11; anchors.verticalCenter: parent.verticalCenter }
                Text { text: qsTr("Search"); font.family: Theme.fontFamily; font.pixelSize: 12; color: "white"; anchors.verticalCenter: parent.verticalCenter }
            }
            Item {
                id: pageDots
                readonly property bool visibleDots: home.pageCount > 1 && (pageDotsTimer.running || touch.paging)
                anchors.fill: parent
                opacity: visibleDots ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Row {
                    id: dotsRow
                    anchors.centerIn: parent
                    spacing: 7
                    Repeater {
                        model: home.pageCount
                        Rectangle {
                            required property int index
                            width: 7; height: 7; radius: 3.5
                            color: "white"
                            opacity: index === home.currentPage ? 1 : 0.35
                        }
                    }
                }
            }
            Timer { id: pageDotsTimer; interval: 1200 }
        }

        Repeater {
            id: repeater
            model: items
            delegate: Item {
                id: cell
                required property int index
                required property string key
                required property string kind
                required property string pkg
                required property string name
                required property string icon
                required property string apps
                required property bool big
                required property string wkey
                required property string wsize
                required property int container
                required property int col
                required property int row
                required property int w
                required property int h
                required property int order

                readonly property bool inDock: container < 0
                readonly property real iconSize: width     // FocusMenu places the icon with it
                readonly property bool dragged: touch.dragging && touch.dragIndex === index
                readonly property real targetX: inDock ? home.dockX(order) : container * home.width + home.cellX(col)
                readonly property real targetY: inDock ? home.dockY + (home.dockHeight - home.dockIconSize) / 2 : home.cellY(row)
                property real lx: targetX
                property real ly: targetY
                Behavior on lx { enabled: home.animateLayout && !cell.dragged; SpringNumberAnimation { preset: Motion.snappy } }
                Behavior on ly { enabled: home.animateLayout && !cell.dragged; SpringNumberAnimation { preset: Motion.snappy } }

                x: dragged ? touch.dragPos.x : (inDock ? 0 : home.pageOffset) + lx
                y: (dragged ? touch.dragPos.y : ly) + drop.value
                z: dragged ? 10 : 0
                width: inDock ? home.dockIconSize : kind === "app" || (kind === "folder" && !big) ? home.iconSize : home.spanW(w)
                height: inDock ? home.dockIconSize : kind === "app" || (kind === "folder" && !big) ? home.iconSize : home.spanH(h)
                scale: dragged ? 1.08 : (touch.dropTarget === index ? 1.15 : 1)
                Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

                // Entrance after unlock: drops from above, rows a beat apart.
                Spring { id: drop; to: 0; response: 0.62; dampingFraction: 0.62 }
                function fall() {
                    drop.snap(-home.height * 0.55 - (cell.inDock ? 4 : cell.row) * 30)
                    fallTimer.interval = (cell.inDock ? 5 : cell.row) * 32 + cell.col * 10
                    fallTimer.restart()
                }
                Timer { id: fallTimer; onTriggered: drop.animateTo(0, 0) }

                // Jiggle while editing
                rotation: home.editing && !dragged ? jiggleAngle : 0
                property real jiggleAngle: 0
                SequentialAnimation on jiggleAngle {
                    running: home.editing
                    loops: Animation.Infinite
                    NumberAnimation { to: cell.kind === "widget" ? 0.8 : 2; duration: 110 + (cell.index % 3) * 15 }
                    NumberAnimation { to: cell.kind === "widget" ? -0.8 : -2; duration: 120 + (cell.index % 3) * 15 }
                }

                HomeIcon {
                    visible: cell.kind === "app"
                    iconSize: cell.width
                    source: cell.icon
                    label: cell.name
                    showLabel: !cell.inDock
                    pressed: touch.pressedIndex === cell.index && !touch.paging && !touch.dragging
                    hidden: focusMenu.index === cell.index && focusMenu.visible || cell.pkg === home.hiddenPackage
                            || (home.appLayer !== null && (home.appLayer.revision, home.appLayer.progress, home.appLayer.isMorphing(cell.pkg)))
                }
                HomeFolder {
                    visible: cell.kind === "folder"
                    anchors.fill: parent
                    name: cell.name
                    apps: cell.kind === "folder" ? JSON.parse(cell.apps) : []
                    big: cell.big
                    pressed: touch.pressedIndex === cell.index && !touch.paging && !touch.dragging
                }
                Loader {
                    active: cell.kind === "widget"
                    anchors.fill: parent
                    sourceComponent: HomeWidget { widgetKey: cell.wkey; size: cell.wsize; shell: home.shell }
                }

                // Remove badge while editing
                Rectangle {
                    visible: home.editing && !cell.dragged && !(cell.kind === "app" && cell.inDock)
                    x: -8; y: -8
                    width: 24; height: 24; radius: 12
                    color: Qt.rgba(0.35, 0.35, 0.38, 0.95)
                    Icon { anchors.centerIn: parent; name: "minus"; size: 14 }
                    z: 3
                }
            }
        }
    }

    // ---- touch handling ----------------------------------------------------
    MouseArea {
        id: touch
        anchors.fill: parent
        enabled: home.interactive
        preventStealing: true

        property point start
        property int pressedIndex: -1
        property bool paging: false
        property bool dragging: false
        property bool longPressed: false
        property int dragIndex: -1
        property point grabOffset
        property point dragPos
        property int dropTarget: -1      // app or folder under the dragged app
        VelocityTracker { id: velocity }

        function inside(item, m) {
            const p = item.mapFromItem(touch, m.x, m.y)
            return item.contains(p)
        }
        function hit(x, y) {
            for (let i = repeater.count - 1; i >= 0; --i) {
                const d = repeater.itemAt(i)
                if (d && !d.dragged && x >= d.x - 6 && x <= d.x + d.width + 6 && y >= d.y - 6 && y <= d.y + d.height + 6)
                    return i
            }
            return -1
        }
        function onBadge(i, x, y) {
            const d = repeater.itemAt(i)
            return home.editing && d && x < d.x + 20 && y < d.y + 20
        }
        function startDrag(i, mx, my) {
            const d = repeater.itemAt(i)
            dragIndex = i
            grabOffset = Qt.point(mx - d.x, my - d.y)
            dragPos = Qt.point(d.x, d.y)
            dragging = true
            home.editing = true
            focusMenu.dismiss()
        }

        onPressed: (m) => {
            start = Qt.point(m.x, m.y)
            pressedIndex = hit(m.x, m.y)
            paging = false
            dragging = false
            longPressed = false
            velocity.reset()
            velocity.addPoint(m.x, m.y)
        }
        pressAndHoldInterval: 480
        onPressAndHold: (m) => {
            if (paging || dragging)
                return
            longPressed = true
            if (pressedIndex < 0) {
                home.editing = true          // hold the background: edit the home screen
                return
            }
            const it = items.get(pressedIndex)
            if (home.editing)
                startDrag(pressedIndex, m.x, m.y)
            else if (it.kind === "app")
                focusMenu.show(pressedIndex)
            else
                startDrag(pressedIndex, m.x, m.y)
        }
        onPositionChanged: (m) => {
            velocity.addPoint(m.x, m.y)
            const dx = m.x - start.x
            const dy = m.y - start.y
            if (dragging) {
                dragPos = Qt.point(m.x - grabOffset.x, m.y - grabOffset.y)
                dragMove(m.x, m.y)
                return
            }
            if ((longPressed || home.editing) && pressedIndex >= 0 && Math.hypot(dx, dy) > 8) {
                startDrag(pressedIndex, m.x, m.y)
                return
            }
            if (!paging && !longPressed && Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy)) {
                paging = true
                pageDotsTimer.restart()
            }
            if (paging) {
                let offset = -home.currentPage * home.width + dx
                const min = -(home.pageCount - 1) * home.width
                if (offset > 0)
                    offset = Motion.rubberband(offset, home.width)
                else if (offset < min)
                    offset = min + Motion.rubberband(offset - min, home.width)
                pager.value = offset
            }
        }
        onReleased: (m) => {
            const v = velocity.velocity()
            if (dragging) {
                drop()
            } else if (paging) {
                const dx = m.x - start.x
                let target = home.currentPage
                if (dx < -home.width * 0.3 || v.x < -500) target++
                else if (dx > home.width * 0.3 || v.x > 500) target--
                home.goToPage(target, v.x)
            } else if (!longPressed) {
                if (pressedIndex >= 0 && onBadge(pressedIndex, m.x, m.y)) {
                    home.removeItem(pressedIndex)
                } else if (pressedIndex >= 0 && !home.editing) {
                    activate(pressedIndex, m)
                } else if (pressedIndex < 0 && home.editing) {
                    home.editing = false
                } else if (pressedIndex < 0 && inside(searchPill, m)) {
                    search.open()
                }
            }
            pressedIndex = -1
            paging = false
            edgeTimer.stop()
        }

        function activate(i, m) {
            const it = items.get(i)
            const d = repeater.itemAt(i)
            if (it.kind === "app") {
                home.launchApp(it.pkg, d)
            } else if (it.kind === "folder") {
                // A big folder opens its first four apps directly.
                const p = d.mapFromItem(touch, m.x, m.y)
                const list = JSON.parse(it.apps)
                if (it.big) {
                    const q = (p.x < d.width / 2 ? 0 : 1) + (p.y < d.height / 2 ? 0 : 2)
                    if (q < 3 || list.length === 4) {
                        if (list[q]) { home.shell.launch(list[q], {}, null); return }
                    }
                }
                folderView.open(it.key, it.name, list, it.big, d)
            } else {
                HomeWidgetActions.activate(it.wkey, home.shell)
            }
        }

        function dragMove(x, y) {
            if (x < 22 || x > home.width - 22) {
                if (!edgeTimer.running) {
                    edgeTimer.direction = x < 22 ? -1 : 1
                    edgeTimer.start()
                }
            } else {
                edgeTimer.stop()
            }
            const it = items.get(dragIndex)
            const d = repeater.itemAt(dragIndex)
            const cx = dragPos.x + d.width / 2
            const cy = dragPos.y + Math.min(d.height, home.iconSize) / 2
            // Over the dock: apps only.
            if (cy > home.dockY - 6) {
                dropTarget = -1
                if (it.kind === "app") {
                    const cell = (home.width - 20) / 4
                    const start0 = 10 + (home.width - 20 - cell * Math.max(1, home.dockCount + (it.container < 0 ? 0 : 1))) / 2
                    const slot = Math.max(0, Math.floor((cx - start0) / cell))
                    if (it.container !== -1 || it.order !== slot)
                        home.moveTo(dragIndex, -1, slot)
                }
                return
            }
            // An app held over another app (or a folder): it will join it.
            if (it.kind === "app") {
                const t = hit(cx, cy)
                if (t >= 0 && t !== dragIndex) {
                    const o = items.get(t)
                    const td = repeater.itemAt(t)
                    const near = Math.hypot(cx - (td.x + td.width / 2), cy - (td.y + Math.min(td.height, home.iconSize) / 2)) < home.iconSize * 0.32
                    if (near && (o.kind === "app" && o.container >= 0 || o.kind === "folder")) {
                        dropTarget = t
                        reorderTimer.stop()
                        return
                    }
                }
            }
            dropTarget = -1
            // Reorder: before the item under the finger, or at the end.
            const page = home.currentPage
            const col = Math.max(0, Math.min(3, Math.floor((cx - home.sidePadding) / home.cellWidth)))
            const row = Math.max(0, Math.min(home.rows - 1, Math.floor((cy - home.gridTop) / home.rowHeight)))
            let order = 1e6
            for (let j = 0; j < items.count; ++j) {
                const o = items.get(j)
                if (j === dragIndex || o.container !== page) continue
                if (row >= o.row && row < o.row + o.h && col >= o.col && col < o.col + o.w) { order = o.order; break }
            }
            if (order === 1e6) {
                let max = 0
                for (let j = 0; j < items.count; ++j)
                    if (j !== dragIndex && items.get(j).container === page) max++
                order = max
            }
            // Like iOS, the others make room once the finger rests a moment,
            // so you can still reach an icon to make a folder.
            if (it.container !== page || it.order !== order) {
                if (reorderTimer.page !== page || reorderTimer.order !== order || !reorderTimer.running) {
                    reorderTimer.page = page
                    reorderTimer.order = order
                    reorderTimer.restart()
                }
            } else {
                reorderTimer.stop()
            }
        }
        Timer {
            id: reorderTimer
            property int page: 0
            property int order: 0
            interval: 260
            onTriggered: if (touch.dragging && touch.dropTarget < 0) home.moveTo(touch.dragIndex, page, order)
        }

        function drop() {
            reorderTimer.stop()
            const target = dropTarget
            const source = dragIndex
            dragging = false
            dropTarget = -1
            if (target >= 0) {
                if (items.get(target).kind === "folder") home.addToFolder(source, target)
                else home.makeFolder(source, target)
                return
            }
            home.relayout()
            home.saveLayout()
        }

        Timer {
            id: edgeTimer
            property int direction: 0
            interval: 550
            repeat: true
            onTriggered: {
                const target = home.currentPage + direction
                if (target < 0 || target > home.pageCount)
                    return
                if (target === home.pageCount)
                    home.pageCount++
                home.goToPage(target, 0)
            }
        }
    }

    // Edit mode: "+" (add a widget) and "Done".
    Rectangle {
        z: 4
        x: 18
        y: Theme.statusBarHeight + 6
        width: 34; height: 30; radius: 15
        color: Qt.rgba(1, 1, 1, 0.22)
        opacity: home.editing && !touch.dragging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Icon { anchors.centerIn: parent; name: "plus"; size: 18 }
        MouseArea { anchors.fill: parent; onClicked: gallery.open() }
    }
    Rectangle {
        z: 4
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: Theme.statusBarHeight + 6
        width: doneText.implicitWidth + 28
        height: 30
        radius: 15
        color: Qt.rgba(1, 1, 1, 0.22)
        opacity: home.editing && !touch.dragging ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Text { id: doneText; anchors.centerIn: parent; text: qsTr("Done"); font.family: Theme.fontFamily; font.pixelSize: 14; font.weight: Font.DemiBold; color: "white" }
        MouseArea { anchors.fill: parent; onClicked: home.editing = false }
    }

    FocusMenu {
        id: focusMenu
        anchors.fill: parent
        z: 6
        home: home
        blurSource: content
        repeater: repeater
        model: items
    }

    FolderView {
        id: folderView
        anchors.fill: parent
        z: 6
        home: home
        blurSource: content
    }

    WidgetGallery {
        id: gallery
        anchors.fill: parent
        z: 7
        blurSource: content
        onAdd: (key, size) => home.addWidget(key, size)
    }

    SearchOverlay {
        id: search
        anchors.fill: parent
        z: 7
        blurSource: content
        onLaunchRequested: (pkg) => home.shell.launch(pkg, {}, null)
    }
}
