// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Maps: OpenStreetMap with search (Photon), places, favourites, and
// directions by car, bike or on foot (OSRM on routing.openstreetmap.de)
// with turn by turn steps that follow your location.
Rectangle {
    id: app
    color: Theme.background

    property bool granted: false
    property var me: null                  // { lat, lon, accuracy }
    property var results: []               // search results
    property var place: null               // the selected place { name, address, lat, lon }
    property string mode: "car"            // car | bike | foot
    property var routeInfo: null           // { distance, duration, steps: [...], line: [[lon, lat]] }
    property bool navigating: false
    property int stepIndex: 0
    readonly property var favorites: Settings.values["app.com.astra.maps.favorites"] || []
    readonly property var recents: Settings.values["app.com.astra.maps.recents"] || []

    function distance(m) {
        return m >= 1000 ? (m / 1000).toFixed(m >= 10000 ? 0 : 1) + " km" : Math.round(m / 10) * 10 + " m"
    }
    function duration(s) {
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60)
        return h ? qsTr("%1 h %2 min").arg(h).arg(m) : qsTr("%1 min").arg(Math.max(1, m))
    }
    function haversine(a, b) {
        const R = 6371000, rad = Math.PI / 180
        const dLa = (b.lat - a.lat) * rad, dLo = (b.lon - a.lon) * rad
        const h = Math.sin(dLa / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLo / 2) ** 2
        return 2 * R * Math.asin(Math.sqrt(h))
    }
    function locate(follow) {
        Location.call("get", { maxAge: 20, watch: !!follow }, function(fix, error) {
            if (!fix) { if (!follow) toast.show(error || qsTr("Location not available")); return }
            app.me = fix
            if (!follow) map.moveTo(fix.lat, fix.lon, Math.max(map.zoom, 15))
        })
    }
    Connections {
        target: Location
        function onStateChanged() {
            const f = Location.state.fix
            if (f && f.lat !== undefined) {
                app.me = f
                if (app.navigating) app.followRoute()
            }
        }
    }

    function search(q) {
        if (!q.trim()) { results = []; return }
        const near = me ? "&lat=" + me.lat + "&lon=" + me.lon : "&lat=" + map.lat + "&lon=" + map.lon
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                const r = JSON.parse(xhr.responseText)
                app.results = r.features.map(f => {
                    const p = f.properties
                    return { name: p.name || p.street || p.city || "", lat: f.geometry.coordinates[1], lon: f.geometry.coordinates[0],
                             address: [p.street ? p.street + (p.housenumber ? " " + p.housenumber : "") : "", p.postcode, p.city, p.country].filter(x => x && x !== p.name).join(", "),
                             kind: p.osm_value || "" }
                })
            } catch (e) {}
        }
        xhr.open("GET", "https://photon.komoot.io/api/?limit=12&lang=" + (["en", "it", "de", "fr"].indexOf(Language.current) >= 0 ? Language.current : "en")
                 + "&q=" + encodeURIComponent(q) + near)
        xhr.send()
    }
    function reverse(lat, lon) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try {
                const p = JSON.parse(xhr.responseText).features[0].properties
                app.select({ name: p.name || (p.street ? p.street + (p.housenumber ? " " + p.housenumber : "") : qsTr("Dropped Pin")), lat: lat, lon: lon,
                             address: [p.postcode, p.city, p.country].filter(x => x).join(", ") })
            } catch (e) { app.select({ name: qsTr("Dropped Pin"), lat: lat, lon: lon, address: lat.toFixed(5) + ", " + lon.toFixed(5) }) }
        }
        xhr.open("GET", "https://photon.komoot.io/reverse?lat=" + lat + "&lon=" + lon)
        xhr.send()
    }
    function select(p) {
        place = p
        routeInfo = null
        navigating = false
        results = []
        panel.state = "place"
        map.moveTo(p.lat, p.lon, Math.max(map.zoom, 15))
        Settings.setValue("app.com.astra.maps.recents", [p].concat(recents.filter(r => r.name !== p.name || r.lat !== p.lat)).slice(0, 12))
    }
    function toggleFavorite(p) {
        const isFav = favorites.some(f => f.lat === p.lat && f.lon === p.lon)
        Settings.setValue("app.com.astra.maps.favorites", isFav ? favorites.filter(f => !(f.lat === p.lat && f.lon === p.lon)) : favorites.concat([p]))
    }
    function directions() {
        if (!place) return
        if (!me) { locate(false); toast.show(qsTr("Finding your location…")); retryRoute.start(); return }
        const profile = { car: "routed-car/route/v1/driving", bike: "routed-bike/route/v1/bike", foot: "routed-foot/route/v1/foot" }[mode]
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            try {
                const r = JSON.parse(xhr.responseText).routes[0]
                const steps = []
                for (const leg of r.legs)
                    for (const s of leg.steps)
                        steps.push({ text: app.instruction(s), distance: s.distance, lat: s.maneuver.location[1], lon: s.maneuver.location[0], type: s.maneuver.type })
                app.routeInfo = { distance: r.distance, duration: r.duration, steps: steps, line: r.geometry.coordinates }
                app.stepIndex = 0
                panel.state = "route"
                map.fit(r.geometry.coordinates)
            } catch (e) { toast.show(qsTr("No route found")) }
        }
        xhr.open("GET", "https://routing.openstreetmap.de/" + profile + "/" + me.lon + "," + me.lat + ";" + place.lon + "," + place.lat
                 + "?overview=full&geometries=geojson&steps=true")
        xhr.send()
    }
    Timer { id: retryRoute; interval: 4000; onTriggered: if (app.me) app.directions() }
    function instruction(s) {
        const road = s.name ? s.name : ""
        const mod = s.maneuver.modifier || ""
        const dir = ({ left: qsTr("left"), right: qsTr("right"), "slight left": qsTr("slightly left"), "slight right": qsTr("slightly right"),
                       "sharp left": qsTr("sharp left"), "sharp right": qsTr("sharp right"), straight: qsTr("straight"), uturn: qsTr("a U-turn") })[mod] || ""
        switch (s.maneuver.type) {
        case "depart": return road ? qsTr("Head out on %1").arg(road) : qsTr("Start")
        case "arrive": return qsTr("Arrive at your destination")
        case "roundabout": case "rotary": return qsTr("At the roundabout, take exit %1").arg(s.maneuver.exit || 1) + (road ? " " + qsTr("onto %1").arg(road) : "")
        case "merge": return qsTr("Merge %1").arg(dir) + (road ? " " + qsTr("onto %1").arg(road) : "")
        default: return (mod === "straight" ? qsTr("Continue straight") : qsTr("Turn %1").arg(dir)) + (road ? " " + qsTr("onto %1").arg(road) : "")
        }
    }
    function startNavigation() {
        navigating = true
        stepIndex = 0
        locate(true)
        followTimer.start()
    }
    Timer { id: followTimer; interval: 15000; repeat: true; running: app.navigating; onTriggered: app.locate(true) }
    function followRoute() {
        if (!routeInfo || !me) return
        // Next step: the first one ahead that we are not within 30 m of.
        while (stepIndex < routeInfo.steps.length - 1 && haversine(me, routeInfo.steps[stepIndex]) < 30) stepIndex++
        map.moveTo(me.lat, me.lon, 17)
        if (haversine(me, place) < 25) { navigating = false; toast.show(qsTr("You have arrived")) }
    }

    Component.onCompleted: Permissions.request("astra.permission.LOCATION", function(ok) {
        app.granted = !!ok
        if (ok) app.locate(false)
        if (Application.args.query) { searchField.text = Application.args.query; app.search(Application.args.query); panel.state = "search" }
    })

    MapView {
        id: map
        anchors.fill: parent
        dark: !Theme.light
        me: app.me
        markers: (app.place ? [{ lat: app.place.lat, lon: app.place.lon, color: "#FF453A" }] : [])
                 .concat(panel.state === "search" ? app.results.slice(0, 10).map(r => ({ lat: r.lat, lon: r.lon, color: "#FF9F0A" })) : [])
        route: app.routeInfo ? app.routeInfo.line : []
        onHeld: (la, lo) => app.reverse(la, lo)
        onTapped: if (panel.state === "search") { panel.state = "home"; searchField.focus = false }
    }

    // Navigation banner
    Rectangle {
        visible: app.navigating && app.routeInfo !== null
        x: 12
        y: Theme.statusBarHeight + 8
        width: parent.width - 24
        height: 96
        radius: Theme.cardRadius
        color: "#1C6B3A"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 18
            spacing: 14
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "navigation"; size: 34; color: "white" }
            Column {
                width: parent.parent.width - 90
                Text { text: app.routeInfo && app.me ? app.distance(app.haversine(app.me, app.routeInfo.steps[app.stepIndex])) : ""; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 26; font.weight: Font.Bold }
                Text { width: parent.width; elide: Text.ElideRight; text: app.routeInfo ? app.routeInfo.steps[app.stepIndex].text : ""; color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize }
            }
        }
    }

    // Map buttons
    Column {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: Theme.statusBarHeight + (app.navigating ? 116 : 12)
        spacing: 1
        Rectangle {
            width: 46; height: 92; radius: 14
            color: Theme.glassPanel
            Column {
                IconButton { iconName: "navigation"; size: 46; color: "transparent"; iconColor: app.me ? "#0A84FF" : Theme.text; onClicked: app.locate(false) }
                IconButton { iconName: "layers"; size: 46; color: "transparent"; onClicked: map.dark = !map.dark }
            }
        }
    }

    // ---- bottom panel ------------------------------------------------------------
    Rectangle {
        id: panel
        state: "home"   // home | search | place | route
        anchors.bottom: parent.bottom
        width: parent.width
        height: state === "search" ? parent.height * 0.75 : content.height + 30 + Theme.homeIndicatorHeight
        Behavior on height { SpringNumberAnimation { preset: Motion.snappy } }
        radius: Theme.sheetRadius
        color: Theme.sheet
        MouseArea { anchors.fill: parent }

        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 7; width: 38; height: 5; radius: 2.5; color: Theme.separator }

        Column {
            id: content
            x: 16
            y: 20
            width: parent.width - 32
            spacing: 14

            // Search
            Rectangle {
                visible: panel.state === "home" || panel.state === "search"
                width: parent.width
                height: 44
                radius: 14
                color: Theme.surfaceRaised
                Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 18; color: Theme.textSecondary }
                TextInput {
                    id: searchField
                    anchors.fill: parent
                    anchors.leftMargin: 40
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.text
                    clip: true
                    onActiveFocusChanged: if (activeFocus) panel.state = "search"
                    onTextEdited: searchTimer.restart()
                    onAccepted: app.search(text)
                    EnterKey.type: Qt.EnterKeySearch
                    Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !parent.text; text: qsTr("Search Maps"); font: parent.font; color: Theme.textTertiary }
                }
                Timer { id: searchTimer; interval: 350; onTriggered: app.search(searchField.text) }
            }

            // Home: favourites and recents
            Column {
                visible: panel.state === "home"
                width: parent.width
                spacing: 10
                Text { text: qsTr("Favorites"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
                Flow {
                    width: parent.width
                    spacing: 14
                    Fav { icon: "navigation"; label: qsTr("My Location"); onClicked: app.locate(false) }
                    Repeater {
                        model: app.favorites.slice(0, 6)
                        delegate: Fav { required property var modelData; icon: "star"; label: modelData.name; onClicked: app.select(modelData) }
                    }
                }
            }

            // Search results / recents
            ListView {
                visible: panel.state === "search"
                width: parent.width
                height: panel.height - 120 - Theme.homeIndicatorHeight
                clip: true
                model: searchField.text ? app.results : app.recents
                header: Text {
                    visible: !searchField.text && app.recents.length > 0
                    height: visible ? 30 : 0
                    text: qsTr("Recents")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize
                    font.weight: Font.Bold
                    color: Theme.textSecondary
                }
                delegate: ListItem {
                    required property var modelData
                    width: ListView.view.width
                    text: modelData.name
                    subtitle: modelData.address + (app.me ? " • " + app.distance(app.haversine(app.me, modelData)) : "")
                    iconName: "location"
                    iconTile: 34
                    tileColor: "#FF453A"
                    onClicked: { searchField.focus = false; app.select(modelData) }
                }
            }

            // Place card
            Column {
                visible: panel.state === "place" && app.place !== null
                width: parent.width
                spacing: 12
                Item {
                    width: parent.width
                    height: placeTitle.height
                    Column {
                        id: placeTitle
                        width: parent.width - 50
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: app.place ? app.place.name : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: app.place ? app.place.address : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                    }
                    IconButton { anchors.right: parent.right; iconName: "close"; size: 34; onClicked: { app.place = null; panel.state = "home" } }
                }
                SegmentedControl {
                    width: parent.width
                    model: [qsTr("Drive"), qsTr("Cycle"), qsTr("Walk")]
                    currentIndex: ["car", "bike", "foot"].indexOf(app.mode)
                    onActivated: (i) => app.mode = ["car", "bike", "foot"][i]
                }
                Row {
                    width: parent.width
                    spacing: 10
                    Button { width: (parent.width - 20) / 2; text: qsTr("Directions"); iconName: "navigation"; onClicked: app.directions() }
                    Button {
                        width: (parent.width - 20) / 4
                        primary: false
                        iconName: "star"
                        text: ""
                        onClicked: app.toggleFavorite(app.place)
                    }
                    Button {
                        width: (parent.width - 20) / 4
                        primary: false
                        iconName: "share"
                        text: ""
                        onClicked: share.open([], "text/plain", "share", app.place.name + "\nhttps://www.openstreetmap.org/?mlat=" + app.place.lat + "&mlon=" + app.place.lon + "#map=17/" + app.place.lat + "/" + app.place.lon)
                    }
                }
            }

            // Route
            Column {
                visible: panel.state === "route" && app.routeInfo !== null
                width: parent.width
                spacing: 12
                Item {
                    width: parent.width
                    height: 54
                    Column {
                        Text { text: app.routeInfo ? app.duration(app.routeInfo.duration) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                        Text {
                            text: app.routeInfo ? app.distance(app.routeInfo.distance) + " • " + qsTr("arrive at %1").arg(Qt.locale().toString(new Date(Date.now() + app.routeInfo.duration * 1000), "HH:mm")) : ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.footnoteSize
                            color: Theme.textSecondary
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Button { visible: !app.navigating; text: qsTr("Go"); width: 86; onClicked: app.startNavigation() }
                        Button { visible: app.navigating; text: qsTr("End"); destructive: true; width: 86; onClicked: { app.navigating = false; panel.state = "place" } }
                        IconButton { iconName: "close"; size: 40; onClicked: { app.routeInfo = null; app.navigating = false; panel.state = "place" } }
                    }
                }
                ListView {
                    width: parent.width
                    height: Math.min(260, contentHeight)
                    clip: true
                    model: app.routeInfo ? app.routeInfo.steps : []
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        text: modelData.text
                        value: modelData.distance > 0 ? app.distance(modelData.distance) : ""
                        selected: app.navigating && index === app.stepIndex
                    }
                }
            }
        }
    }

    component Fav: Column {
        id: fav
        property string icon
        property string label
        signal clicked()
        spacing: 6
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56; height: 56; radius: 28
            color: Theme.surfaceRaised
            Icon { anchors.centerIn: parent; name: fav.icon; size: 24; color: "#0A84FF" }
            MouseArea { anchors.fill: parent; onClicked: fav.clicked() }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; width: 70; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: fav.label; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.text }
    }

    ShareSheet { id: share }

    Rectangle {
        id: toast
        function show(t) { toastText.text = t; opacity = 1; toastTimer.restart() }
        z: 90
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.statusBarHeight + 60
        width: toastText.implicitWidth + 32; height: 40; radius: 20
        color: "#3A3A42"
        Text { id: toastText; anchors.centerIn: parent; color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
        Timer { id: toastTimer; interval: 2400; onTriggered: toast.opacity = 0 }
    }
}
