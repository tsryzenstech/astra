// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Astra.Controls

// A slippy map of OpenStreetMap raster tiles (Web Mercator). Drag to pan, pinch or
// double tap to zoom. Markers and a route line are drawn on top.
Item {
    id: map
    clip: true

    property real lat: 45.4642
    property real lon: 9.19
    property real zoom: 12
    property bool dark: false
    property var markers: []          // [{ lat, lon, color, label }]
    property var route: []            // [[lon, lat], ...]
    property var me: null             // { lat, lon, accuracy }
    signal tapped(real lat, real lon)
    signal held(real lat, real lon)

    readonly property int tileZoom: Math.max(1, Math.min(19, Math.floor(zoom)))
    readonly property real tileScale: Math.pow(2, zoom - tileZoom)
    readonly property real tileSize: 256 * tileScale

    // World pixel coordinates at the current zoom.
    function worldX(lo, z) { return (lo + 180) / 360 * 256 * Math.pow(2, z) }
    function worldY(la, z) {
        const s = Math.sin(la * Math.PI / 180)
        return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * 256 * Math.pow(2, z)
    }
    function lonAt(x, z) { return x / (256 * Math.pow(2, z)) * 360 - 180 }
    function latAt(y, z) {
        const n = Math.PI - 2 * Math.PI * y / (256 * Math.pow(2, z))
        return 180 / Math.PI * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))
    }
    readonly property real cx: worldX(lon, zoom)
    readonly property real cy: worldY(lat, zoom)
    function screenPoint(la, lo) { return Qt.point(worldX(lo, zoom) - cx + width / 2, worldY(la, zoom) - cy + height / 2) }
    function coordAt(x, y) { return { lat: latAt(cy + y - height / 2, zoom), lon: lonAt(cx + x - width / 2, zoom) } }

    function moveTo(la, lo, z) {
        anim.stop()
        anim.toLat = la
        anim.toLon = lo
        anim.toZoom = z === undefined ? zoom : z
        anim.start()
    }
    function fit(points) {
        if (!points.length)
            return
        let minLa = 90, maxLa = -90, minLo = 180, maxLo = -180
        for (const p of points) { minLa = Math.min(minLa, p[1]); maxLa = Math.max(maxLa, p[1]); minLo = Math.min(minLo, p[0]); maxLo = Math.max(maxLo, p[0]) }
        let z = 17
        while (z > 2 && (worldX(maxLo, z) - worldX(minLo, z) > width * 0.8 || worldY(minLa, z) - worldY(maxLa, z) > height * 0.6)) z -= 0.25
        moveTo((minLa + maxLa) / 2, (minLo + maxLo) / 2, z)
    }
    ParallelAnimation {
        id: anim
        property real toLat
        property real toLon
        property real toZoom
        NumberAnimation { target: map; property: "lat"; to: anim.toLat; duration: 600; easing.type: Easing.InOutCubic }
        NumberAnimation { target: map; property: "lon"; to: anim.toLon; duration: 600; easing.type: Easing.InOutCubic }
        NumberAnimation { target: map; property: "zoom"; to: anim.toZoom; duration: 600; easing.type: Easing.InOutCubic }
    }

    Rectangle { anchors.fill: parent; color: map.dark ? "#1B1C1F" : "#F2EFE9" }

    // Tiles (OpenStreetMap), dimmed for the dark appearance.
    Item {
        id: tiles
        anchors.fill: parent        // the layer needs a size
        layer.enabled: map.dark
        layer.effect: MultiEffect { brightness: -0.42; saturation: -0.35; contrast: 0.1 }
        readonly property real originX: map.worldX(map.lon, map.tileZoom) * map.tileScale - map.width / 2
        readonly property real originY: map.worldY(map.lat, map.tileZoom) * map.tileScale - map.height / 2
        readonly property int firstX: Math.floor(originX / map.tileSize)
        readonly property int firstY: Math.floor(originY / map.tileSize)
        readonly property int cols: Math.ceil(map.width / map.tileSize) + 1
        readonly property int rows: Math.ceil(map.height / map.tileSize) + 1
        Repeater {
            model: tiles.cols * tiles.rows
            delegate: Image {
                required property int index
                readonly property int tx: tiles.firstX + index % tiles.cols
                readonly property int ty: tiles.firstY + Math.floor(index / tiles.cols)
                readonly property int n: Math.pow(2, map.tileZoom)
                x: tx * map.tileSize - tiles.originX
                y: ty * map.tileSize - tiles.originY
                width: map.tileSize + 0.5
                height: map.tileSize + 0.5
                visible: ty >= 0 && ty < n
                asynchronous: true
                cache: true
                smooth: true
                source: visible ? "https://tile.openstreetmap.org/" + map.tileZoom + "/" + (((tx % n) + n) % n) + "/" + ty + ".png" : ""
                sourceSize: Qt.size(256, 256)
            }
        }
    }

    // Route
    Shape {
        anchors.fill: parent
        visible: map.route.length > 1
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 7
            strokeColor: "#0A84FF"
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline {
                path: map.route.map(p => map.screenPoint(p[1], p[0]))
            }
        }
    }

    // Markers
    Repeater {
        model: map.markers
        delegate: Item {
            required property var modelData
            readonly property point p: map.screenPoint(modelData.lat, modelData.lon)
            x: p.x - 16
            y: p.y - 40
            width: 32
            height: 40
            Rectangle {
                width: 32; height: 32; radius: 16
                color: modelData.color || "#FF453A"
                border.width: 3
                border.color: "white"
                Icon { anchors.centerIn: parent; name: "location"; size: 16; color: "white" }
            }
            Rectangle { x: 14; y: 30; width: 4; height: 10; radius: 2; color: "white" }
        }
    }

    // Current location
    Item {
        visible: map.me !== null
        readonly property point p: map.me ? map.screenPoint(map.me.lat, map.me.lon) : Qt.point(0, 0)
        readonly property real metersPerPixel: map.me ? 156543.03 * Math.cos(map.me.lat * Math.PI / 180) / Math.pow(2, map.zoom) : 1
        Rectangle {
            readonly property real r: map.me ? Math.min(400, (map.me.accuracy || 30) / parent.metersPerPixel) : 0
            x: parent.p.x - r; y: parent.p.y - r
            width: r * 2; height: r * 2; radius: r
            color: Qt.rgba(0.04, 0.52, 1, 0.15)
            border.color: Qt.rgba(0.04, 0.52, 1, 0.35)
        }
        Rectangle {
            x: parent.p.x - 11; y: parent.p.y - 11
            width: 22; height: 22; radius: 11
            color: "#0A84FF"
            border.width: 3
            border.color: "white"
        }
    }

    // Gestures
    DragHandler {
        id: drag
        target: null
        property real startLat
        property real startLon
        onActiveChanged: if (active) { anim.stop(); startLat = map.lat; startLon = map.lon }
        onTranslationChanged: {
            if (!active)
                return
            const x0 = map.worldX(startLon, map.zoom) - translation.x
            const y0 = map.worldY(startLat, map.zoom) - translation.y
            map.lon = map.lonAt(x0, map.zoom)
            map.lat = Math.max(-85, Math.min(85, map.latAt(y0, map.zoom)))
        }
    }
    PinchHandler {
        target: null
        property real startZoom
        onActiveChanged: if (active) { anim.stop(); startZoom = map.zoom }
        onActiveScaleChanged: if (active) map.zoom = Math.max(2, Math.min(19, startZoom + Math.log2(activeScale)))
    }
    WheelHandler {
        onWheel: (e) => map.zoom = Math.max(2, Math.min(19, map.zoom + e.angleDelta.y / 240))
    }
    TapHandler {
        onDoubleTapped: (point) => {
            const c = map.coordAt(point.position.x, point.position.y)
            map.moveTo(c.lat, c.lon, Math.min(19, map.zoom + 1))
        }
        onSingleTapped: (point) => { const c = map.coordAt(point.position.x, point.position.y); map.tapped(c.lat, c.lon) }
        onLongPressed: { const c = map.coordAt(point.position.x, point.position.y); map.held(c.lat, c.lon) }
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 4
        text: "© OpenStreetMap contributors"
        font.pixelSize: 9
        color: map.dark ? "#AAAAAA" : "#555555"
    }
}
