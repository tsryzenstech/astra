// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// The home screen (HomeConfig1.png). Part of SysBoard: it cannot be
// replaced by apps.
//
// Every icon lives in one model as (container, slot): container -1 is the
// dock, 0..n are pages. Moving icons only changes slots, so delegates are
// never recreated and every displacement animates with a spring.
Item {
    id: home

    property var shell
    property real appProgress: 0
    property bool interactive: true
    property bool editing: false
    property bool animateLayout: false

    // ---- geometry (reference: 393 x 852 logical px) ----------------------
    readonly property real sidePadding: 10
    readonly property real cellWidth: (width - 2 * sidePadding) / 4
    readonly property real iconSize: 62
    readonly property real dockIconSize: 70
    readonly property real rowHeight: 106
    readonly property real dockHeight: 107
    readonly property real dockY: height - 37 - dockHeight
    readonly property real firstPageGridTop: 444
    readonly property real gridTop: 96
    readonly property int firstPageCapacity: 8
    readonly property int pageCapacity: Math.max(4, Math.floor((dockY - 50 - gridTop) / rowHeight) * 4)

    function capacity(container) {
        return container < 0 ? 4 : container === 0 ? firstPageCapacity : pageCapacity
    }
    function localX(container, slot) {
        if (container < 0) {
            const cell = (width - 20) / 4
            return 10 + cell * slot + (cell - dockIconSize) / 2
        }
        return sidePadding + cellWidth * (slot % 4) + (cellWidth - iconSize) / 2
    }
    function localY(container, slot) {
        if (container < 0)
            return dockY + (dockHeight - dockIconSize) / 2
        return (container === 0 ? firstPageGridTop : gridTop) + rowHeight * Math.floor(slot / 4)
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

    // ---- layout model ----------------------------------------------------
    ListModel { id: icons }

    function indexOf(pkg) {
        for (let i = 0; i < icons.count; ++i)
            if (icons.get(i).pkg === pkg)
                return i
        return -1
    }
    function countIn(container, except) {
        let n = 0
        for (let i = 0; i < icons.count; ++i)
            if (icons.get(i).container === container && i !== except)
                n++
        return n
    }

    function rebuild() {
        if (!Packages.ready || !Settings.ready)
            return
        const layout = Settings.values["home.layout"] || { pages: [[]], dock: [] }
        const installed = {}
        for (const p of Packages.list())
            if (p.launcher)
                installed[p.package] = p

        const wanted = []
        const placed = {}
        const place = (pkg, container, slot) => {
            placed[pkg] = true
            wanted.push({ pkg: pkg, container: container, slot: slot })
        }
        let slot = 0
        for (const pkg of (layout.dock || []))
            if (installed[pkg] && !placed[pkg] && slot < 4)
                place(pkg, -1, slot++)
        const pages = layout.pages && layout.pages.length ? layout.pages : [[]]
        let page = 0
        for (; page < pages.length; ++page) {
            slot = 0
            for (const pkg of pages[page])
                if (installed[pkg] && !placed[pkg] && slot < capacity(page))
                    place(pkg, page, slot++)
        }
        // New apps go to the first free slot from the last page on.
        page = Math.max(0, pages.length - 1)
        for (const pkg of Object.keys(installed).sort()) {
            if (placed[pkg])
                continue
            while (wanted.filter(w => w.container === page).length >= capacity(page))
                page++
            place(pkg, page, wanted.filter(w => w.container === page).length)
        }

        // Reconcile the model in place so existing icons animate.
        for (let i = icons.count - 1; i >= 0; --i)
            if (!placed[icons.get(i).pkg])
                icons.remove(i)
        for (const w of wanted) {
            const p = installed[w.pkg]
            const i = indexOf(w.pkg)
            const data = { pkg: w.pkg, name: p.name, icon: p.iconUrl.toString(), container: w.container,
                           slot: w.slot, system: p.system, background: p.background }
            if (i < 0)
                icons.append(data)
            else
                icons.set(i, data)
        }
        compact(false)
    }

    // Removes empty pages (never the first one) and recomputes pageCount.
    function compact(save) {
        let maxPage = 0
        const used = {}
        for (let i = 0; i < icons.count; ++i) {
            const c = icons.get(i).container
            if (c >= 0)
                used[c] = true
        }
        const remap = {}
        let next = 1 // page 0 always exists
        const sortedPages = Object.keys(used).map(Number).sort((a, b) => a - b)
        for (const c of sortedPages)
            remap[c] = c === 0 ? 0 : next++
        for (let i = 0; i < icons.count; ++i) {
            const c = icons.get(i).container
            if (c > 0 && remap[c] !== c)
                icons.setProperty(i, "container", remap[c])
            maxPage = Math.max(maxPage, c >= 0 ? remap[c] : 0)
        }
        pageCount = maxPage + 1
        if (currentPage >= pageCount)
            goToPage(pageCount - 1)
        if (save)
            saveLayout()
    }

    function saveLayout() {
        const pages = []
        const dock = []
        for (let i = 0; i < icons.count; ++i) {
            const it = icons.get(i)
            if (it.container < 0) {
                dock[it.slot] = it.pkg
            } else {
                while (pages.length <= it.container)
                    pages.push([])
                pages[it.container][it.slot] = it.pkg
            }
        }
        Settings.setValue("home.layout", { pages: pages.map(p => p.filter(x => !!x)), dock: dock.filter(x => !!x) })
    }

    // Moves an icon, shifting the others like iOS does. Returns false when
    // the target container is full.
    function moveIcon(index, container, slot) {
        const it = icons.get(index)
        const from = it.container
        const fromSlot = it.slot
        if (from === container) {
            slot = Math.max(0, Math.min(slot, countIn(container, -1) - 1))
            if (slot === fromSlot)
                return true
            for (let i = 0; i < icons.count; ++i) {
                const o = icons.get(i)
                if (i === index || o.container !== container)
                    continue
                if (fromSlot < slot && o.slot > fromSlot && o.slot <= slot)
                    icons.setProperty(i, "slot", o.slot - 1)
                else if (slot < fromSlot && o.slot >= slot && o.slot < fromSlot)
                    icons.setProperty(i, "slot", o.slot + 1)
            }
        } else {
            const count = countIn(container, index)
            if (count >= capacity(container))
                return false
            slot = Math.max(0, Math.min(slot, count))
            for (let i = 0; i < icons.count; ++i) {
                const o = icons.get(i)
                if (i === index)
                    continue
                if (o.container === from && o.slot > fromSlot)
                    icons.setProperty(i, "slot", o.slot - 1)
                else if (o.container === container && o.slot >= slot)
                    icons.setProperty(i, "slot", o.slot + 1)
            }
        }
        icons.setProperty(index, "container", container)
        icons.setProperty(index, "slot", slot)
        if (container >= pageCount)
            pageCount = container + 1
        return true
    }

    // Screen rect of an icon, used by app open/close transitions.
    function iconRect(pkg) {
        const i = indexOf(pkg)
        if (i < 0)
            return null
        const it = icons.get(i)
        if (it.container >= 0 && it.container !== currentPage)
            return null
        const d = iconRepeater.itemAt(i)
        return d ? d.mapToItem(home, 0, 0, d.iconSize, d.iconSize) : null
    }

    function launch(index) {
        const d = iconRepeater.itemAt(index)
        const it = icons.get(index)
        shell.launch(it.pkg, {}, d.mapToItem(home, 0, 0, d.iconSize, d.iconSize))
    }

    Connections {
        target: Packages
        function onCountChanged() { home.rebuild() }
        function onReadyChanged() { home.rebuild() }
    }
    Connections {
        target: Settings
        function onValuesChanged() { if (icons.count === 0) home.rebuild() }
    }
    Component.onCompleted: {
        rebuild()
        Qt.callLater(() => home.animateLayout = true)
    }

    // ---- content -----------------------------------------------------------
    Item {
        id: content
        anchors.fill: parent
        opacity: 1 - home.appProgress
        scale: 1 + 0.08 * home.appProgress

        Image {
            anchors.fill: parent
            source: Host.wallpaper
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(width * 2, height * 2)
            asynchronous: true
        }

        // First page header: weather greeting, Cosmo search, Planet label.
        Item {
            x: home.pageOffset
            width: home.width
            height: home.firstPageGridTop

            Greeting {
                x: 28
                y: 168
            }

            Rectangle {
                id: cosmoBar
                x: 26
                y: 355
                width: parent.width - 52
                height: 40
                radius: 20
                color: Qt.rgba(0, 0, 0, 0.3)
                Text {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Search with Cosmo.."
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
                Image {
                    anchors.right: parent.right
                    anchors.rightMargin: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    source: "icons/system/cosmo-glyph.svg"
                    sourceSize: Qt.size(60, 60)
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 404
                textFormat: Text.StyledText
                text: "<b>Planet</b> • AI Search"
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Normal
                color: Qt.rgba(1, 1, 1, 0.92)
            }
        }

        Rectangle {
            id: dock
            x: 10
            y: home.dockY
            width: home.width - 20
            height: home.dockHeight
            radius: 42
            color: Qt.rgba(0, 0, 0, 0.28)
        }

        // Search pill; shows page dots while paging.
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
                Text {
                    text: "Search"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
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
                            width: 7
                            height: 7
                            radius: 3.5
                            color: "white"
                            opacity: index === home.currentPage ? 1 : 0.35
                        }
                    }
                }
            }
            Timer { id: pageDotsTimer; interval: 1200 }
        }

        Repeater {
            id: iconRepeater
            model: icons

            delegate: HomeIcon {
                required property int index
                required property string pkg
                required property string name
                required property string icon
                required property int container
                required property int slot

                iconSize: container < 0 ? home.dockIconSize : home.iconSize
                source: icon
                label: name
                showLabel: container >= 0
                pressed: touch.pressedIndex === index && !touch.paging && !touch.dragging
                jiggle: home.editing
                hidden: touch.dragging && touch.dragIndex === index || focusMenu.index === index && focusMenu.visible

                readonly property real targetX: home.localX(container, slot)
                readonly property real targetY: home.localY(container, slot)
                property real lx: targetX
                property real ly: targetY
                Behavior on lx { enabled: home.animateLayout; SpringNumberAnimation { preset: Motion.snappy } }
                Behavior on ly { enabled: home.animateLayout; SpringNumberAnimation { preset: Motion.snappy } }

                x: (container >= 0 ? container * home.width + home.pageOffset : 0) + lx
                y: ly
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
        VelocityTracker { id: velocity }

        function inside(item, m) {
            const p = item.mapFromItem(touch, m.x, m.y)
            return item.contains(p)
        }

        function hit(x, y) {
            for (let i = 0; i < iconRepeater.count; ++i) {
                const d = iconRepeater.itemAt(i)
                if (d && x >= d.x - 6 && x <= d.x + d.iconSize + 6 && y >= d.y - 6 && y <= d.y + d.iconSize + 6)
                    return i
            }
            return -1
        }

        function startDrag(i, mx, my) {
            const d = iconRepeater.itemAt(i)
            dragIndex = i
            dragging = true
            home.editing = true
            focusMenu.dismiss()
            grabOffset = Qt.point(mx - d.x, my - d.y)
            proxy.source = d.source
            proxy.size = d.iconSize
            proxy.x = d.x
            proxy.y = d.y
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
            if (paging || dragging || pressedIndex < 0)
                return
            longPressed = true
            if (home.editing)
                startDrag(pressedIndex, m.x, m.y)
            else
                focusMenu.show(pressedIndex)
        }
        onPositionChanged: (m) => {
            velocity.addPoint(m.x, m.y)
            const dx = m.x - start.x
            const dy = m.y - start.y
            if (dragging) {
                proxy.x = m.x - grabOffset.x
                proxy.y = m.y - grabOffset.y
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
                if (dx < -home.width * 0.3 || v.x < -500)
                    target++
                else if (dx > home.width * 0.3 || v.x > 500)
                    target--
                home.goToPage(target, v.x)
            } else if (!longPressed) {
                if (pressedIndex >= 0 && !home.editing)
                    home.launch(pressedIndex)
                else if (pressedIndex < 0 && home.editing)
                    home.editing = false
                else if (pressedIndex < 0 && inside(cosmoBar, m))
                    home.shell.launch("com.astra.planet", { mode: "search" }, null)
                else if (pressedIndex < 0 && inside(searchPill, m))
                    search.open()
            }
            pressedIndex = -1
            paging = false
            edgeTimer.stop()
        }

        function dragMove(x, y) {
            // Hold at the screen edge to change page.
            if (x < 22 || x > home.width - 22) {
                if (!edgeTimer.running) {
                    edgeTimer.direction = x < 22 ? -1 : 1
                    edgeTimer.start()
                }
            } else {
                edgeTimer.stop()
            }
            const cx = x - grabOffset.x + proxy.size / 2
            const cy = y - grabOffset.y + proxy.size / 2
            let container, slot
            if (cy > home.dockY - 6) {
                container = -1
                slot = Math.floor((cx - 10) / ((home.width - 20) / 4))
            } else {
                container = home.currentPage
                const top = container === 0 ? home.firstPageGridTop : home.gridTop
                const rows = home.capacity(container) / 4
                const col = Math.max(0, Math.min(3, Math.floor((cx - home.sidePadding) / home.cellWidth)))
                const row = Math.max(0, Math.min(rows - 1, Math.floor((cy - top + 20) / home.rowHeight)))
                slot = row * 4 + col
            }
            const it = icons.get(dragIndex)
            if (it.container !== container || it.slot !== slot)
                home.moveIcon(dragIndex, container, slot)
        }

        function drop() {
            const d = iconRepeater.itemAt(dragIndex)
            proxy.flyTo(d.x, d.y, d.iconSize)
            dragging = false
            home.compact(true)
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

    // Icon following the finger while dragging.
    AppIcon {
        id: proxy
        visible: touch.dragging || flyX.running || flyY.running
        z: 5
        scale: touch.dragging ? 1.12 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.snappy } }
        function flyTo(x, y, s) {
            flyX.to = x
            flyY.to = y
            size = s
            flyX.restart()
            flyY.restart()
        }
        SpringNumberAnimation on x { id: flyX; running: false; preset: Motion.snappy }
        SpringNumberAnimation on y { id: flyY; running: false; preset: Motion.snappy }
    }

    // "Done" while rearranging.
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
        Text {
            id: doneText
            anchors.centerIn: parent
            text: "Done"
            font.family: Theme.fontFamily
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: "white"
        }
        MouseArea { anchors.fill: parent; onClicked: home.editing = false }
    }

    FocusMenu {
        id: focusMenu
        anchors.fill: parent
        z: 6
        home: home
        blurSource: content
        repeater: iconRepeater
        model: icons
    }

    SearchOverlay {
        id: search
        anchors.fill: parent
        z: 7
        blurSource: content
        onLaunchRequested: (pkg) => home.shell.launch(pkg, {}, null)
    }
}
