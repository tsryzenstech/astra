// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Home: control your smart home through Home Assistant (REST API with a
// long-lived access token). Lights, switches, plugs, fans, covers, locks,
// climate, scenes and sensors as tiles; tap to toggle, hold for details.
Rectangle {
    id: app
    color: Theme.background

    readonly property string configPath: Files.appData + "/home.json"
    property string server: ""
    property string token: ""
    property var pinned: []
    property var entities: []
    property string error: ""
    property bool loading: false
    readonly property bool configured: server !== "" && token !== ""

    readonly property var domains: [
        { id: "scene", title: qsTr("Scenes"), icon: "scene" },
        { id: "light", title: qsTr("Lights"), icon: "bulb" },
        { id: "switch", title: qsTr("Switches"), icon: "plug" },
        { id: "fan", title: qsTr("Fans"), icon: "fan" },
        { id: "cover", title: qsTr("Blinds and Doors"), icon: "door" },
        { id: "lock", title: qsTr("Locks"), icon: "lock" },
        { id: "climate", title: qsTr("Climate"), icon: "thermometer" },
        { id: "media_player", title: qsTr("Speakers and TVs"), icon: "speaker" },
        { id: "sensor", title: qsTr("Sensors"), icon: "thermometer" },
        { id: "binary_sensor", title: qsTr("Detectors"), icon: "shield" }
    ]
    function domainOf(e) { return e.entity_id.split(".")[0] }
    function nameOf(e) { return (e.attributes && e.attributes.friendly_name) || e.entity_id }
    function isOn(e) { return ["on", "open", "unlocked", "playing", "heat", "cool", "auto", "heat_cool"].indexOf(e.state) >= 0 }
    function stateText(e) {
        const d = domainOf(e)
        if (d === "sensor") return e.state + (e.attributes.unit_of_measurement ? " " + e.attributes.unit_of_measurement : "")
        if (d === "climate") return (e.attributes.current_temperature !== undefined ? e.attributes.current_temperature + "° • " : "") + e.state
        if (d === "light" && e.state === "on" && e.attributes.brightness) return Math.round(e.attributes.brightness / 2.55) + "%"
        if (d === "scene") return qsTr("Scene")
        return { on: qsTr("On"), off: qsTr("Off"), open: qsTr("Open"), closed: qsTr("Closed"), locked: qsTr("Locked"), unlocked: qsTr("Unlocked"),
                 unavailable: qsTr("Unavailable"), playing: qsTr("Playing"), paused: qsTr("Paused"), idle: qsTr("Idle") }[e.state] || e.state
    }

    function loadConfig() {
        try {
            const c = JSON.parse(Files.readText(configPath) || "{}")
            server = c.server || ""
            token = c.token || ""
            pinned = c.pinned || []
        } catch (e) {}
    }
    function saveConfig() { Files.writeText(configPath, JSON.stringify({ server: server, token: token, pinned: pinned })) }

    function api(method, path, body, done) {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status >= 200 && xhr.status < 300) {
                app.error = ""
                try { done(JSON.parse(xhr.responseText || "null")) } catch (e) { done(null) }
            } else {
                app.error = xhr.status === 401 ? qsTr("The access token was refused.") : xhr.status === 0 ? qsTr("Home Assistant is not reachable.") : qsTr("Error %1").arg(xhr.status)
                app.loading = false
            }
        }
        xhr.open(method, server.replace(/\/$/, "") + path)
        xhr.setRequestHeader("Authorization", "Bearer " + token)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(body ? JSON.stringify(body) : "")
    }
    function refresh() {
        if (!configured) return
        loading = true
        api("GET", "/api/states", null, function(list) {
            app.loading = false
            const known = app.domains.map(d => d.id)
            app.entities = (list || []).filter(e => known.indexOf(e.entity_id.split(".")[0]) >= 0 && !(e.attributes && e.attributes.hidden))
        })
    }
    function call(domain, service, data) {
        api("POST", "/api/services/" + domain + "/" + service, data, function() { refreshSoon.restart() })
    }
    Timer { id: refreshSoon; interval: 600; onTriggered: app.refresh() }
    Timer { interval: 10000; repeat: true; running: app.configured && Qt.application.state === Qt.ApplicationActive; onTriggered: app.refresh() }
    function toggle(e) {
        const d = domainOf(e)
        if (d === "scene") call("scene", "turn_on", { entity_id: e.entity_id })
        else if (d === "lock") call("lock", e.state === "locked" ? "unlock" : "lock", { entity_id: e.entity_id })
        else if (d === "cover") call("cover", e.state === "open" ? "close_cover" : "open_cover", { entity_id: e.entity_id })
        else if (d === "media_player") call("media_player", "media_play_pause", { entity_id: e.entity_id })
        else if (d === "climate") detail.show(e)
        else if (d === "sensor" || d === "binary_sensor") detail.show(e)
        else call("homeassistant", "toggle", { entity_id: e.entity_id })
        // Optimistic state so the tile reacts right away.
        if (["light", "switch", "fan"].indexOf(d) >= 0)
            entities = entities.map(x => x.entity_id === e.entity_id ? Object.assign({}, x, { state: x.state === "on" ? "off" : "on" }) : x)
    }
    function togglePin(e) {
        pinned = pinned.indexOf(e.entity_id) >= 0 ? pinned.filter(p => p !== e.entity_id) : pinned.concat([e.entity_id])
        saveConfig()
    }

    Component.onCompleted: { loadConfig(); refresh() }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(homePage)
    }

    Component {
        id: homePage
        Page {
            title: qsTr("My Home")
            actions: Row {
                spacing: 8
                Spinner { visible: app.loading; anchors.verticalCenter: parent.verticalCenter }
                IconButton { iconName: "settings"; size: 38; onClicked: stack.open(setupPage) }
            }

            Column {
                visible: !app.configured
                width: parent.width
                spacing: 16
                EmptyState {
                    width: parent.width
                    iconName: "home"
                    title: qsTr("Set Up Your Home")
                    message: qsTr("Home controls the lights, plugs, blinds, locks and thermostats you have in Home Assistant.")
                }
                Button { width: parent.width; text: qsTr("Connect to Home Assistant"); onClicked: stack.open(setupPage) }
            }
            Card {
                visible: app.error !== ""
                width: parent.width
                Text { width: parent.width; wrapMode: Text.WordWrap; text: app.error; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize }
            }

            Section {
                visible: app.configured && app.pinned.length > 0
                title: qsTr("Favorites")
                list: app.entities.filter(e => app.pinned.indexOf(e.entity_id) >= 0)
            }
            Repeater {
                model: app.configured ? app.domains : []
                delegate: Section {
                    required property var modelData
                    title: modelData.title
                    list: app.entities.filter(e => app.domainOf(e) === modelData.id)
                    visible: list.length > 0
                }
            }
        }
    }

    component Section: Column {
        id: section
        property string title
        property var list: []
        width: parent ? parent.width : 300
        spacing: 10
        Text { text: section.title; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
        Grid {
            width: parent.width
            columns: 2
            spacing: 10
            Repeater {
                model: section.list
                delegate: Tile { required property var modelData; entity: modelData; width: (section.width - 10) / 2 }
            }
        }
    }

    component Tile: Rectangle {
        id: tile
        property var entity
        readonly property bool on: app.isOn(entity)
        readonly property string icon: (app.domains.find(d => d.id === app.domainOf(entity)) || { icon: "home" }).icon
        height: 76
        radius: 20
        color: on ? (Theme.light ? "#FFFFFF" : "#F2F2F7") : Theme.surface
        opacity: entity.state === "unavailable" ? 0.45 : 1
        scale: tileArea.pressed ? 0.96 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40; radius: 20
            color: tile.on ? (app.domainOf(tile.entity) === "light" ? "#FFD60A" : Theme.accent) : Theme.surfaceRaised
            Icon { anchors.centerIn: parent; name: tile.icon; size: 22; color: tile.on ? "#1C1C1E" : Theme.text }
        }
        Column {
            x: 62
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 70
            Text { width: parent.width; elide: Text.ElideRight; text: app.nameOf(tile.entity); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; font.weight: Font.DemiBold; color: tile.on ? "#1C1C1E" : Theme.text }
            Text { width: parent.width; elide: Text.ElideRight; text: app.stateText(tile.entity); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: tile.on ? "#3A3A3C" : Theme.textSecondary }
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            onClicked: app.toggle(tile.entity)
            onPressAndHold: detail.show(tile.entity)
        }
    }

    // ---- details ------------------------------------------------------------
    Item {
        id: detail
        property var entity: null
        readonly property var live: entity ? (app.entities.find(e => e.entity_id === entity.entity_id) || entity) : null
        function show(e) { entity = e; rv.animateTo(1, 0) }
        function close() { rv.animateTo(0, 0) }
        anchors.fill: parent
        z: 40
        visible: rv.value > 0.01
        Spring { id: rv; to: 0; response: 0.38; dampingFraction: 0.84 }
        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.45 * rv.value; MouseArea { anchors.fill: parent; onClicked: detail.close() } }
        Rectangle {
            width: parent.width
            height: dcol.height + 40 + Theme.homeIndicatorHeight
            y: parent.height - height * rv.value
            radius: Theme.sheetRadius
            color: Theme.sheet
            MouseArea { anchors.fill: parent }
            Column {
                id: dcol
                x: 20; y: 24
                width: parent.width - 40
                spacing: 16
                Text { text: detail.live ? app.nameOf(detail.live) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
                Text { text: detail.live ? app.stateText(detail.live) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }

                // Light brightness
                Slider {
                    visible: detail.live && app.domainOf(detail.live) === "light"
                    width: parent.width
                    from: 0; to: 100
                    value: detail.live && detail.live.attributes.brightness ? detail.live.attributes.brightness / 2.55 : 0
                    onMoved: app.call("light", value < 1 ? "turn_off" : "turn_on", value < 1 ? { entity_id: detail.live.entity_id } : { entity_id: detail.live.entity_id, brightness_pct: Math.round(value) })
                }
                // Thermostat
                Row {
                    visible: detail.live && app.domainOf(detail.live) === "climate"
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 24
                    readonly property real target: detail.live && detail.live.attributes.temperature !== undefined ? detail.live.attributes.temperature : 20
                    IconButton { iconName: "minus"; size: 52; onClicked: app.call("climate", "set_temperature", { entity_id: detail.live.entity_id, temperature: parent.target - 0.5 }) }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: parent.target.toFixed(1) + "°"; font.family: Theme.fontFamily; font.pixelSize: 44; font.weight: Font.Light; color: Theme.text }
                    IconButton { iconName: "plus"; size: 52; onClicked: app.call("climate", "set_temperature", { entity_id: detail.live.entity_id, temperature: parent.target + 0.5 }) }
                }
                // Media
                Row {
                    visible: detail.live && app.domainOf(detail.live) === "media_player"
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20
                    IconButton { iconName: "previous"; size: 50; onClicked: app.call("media_player", "media_previous_track", { entity_id: detail.live.entity_id }) }
                    IconButton { iconName: detail.live && detail.live.state === "playing" ? "pause" : "play"; size: 58; color: Theme.accent; onClicked: app.call("media_player", "media_play_pause", { entity_id: detail.live.entity_id }) }
                    IconButton { iconName: "next"; size: 50; onClicked: app.call("media_player", "media_next_track", { entity_id: detail.live.entity_id }) }
                }
                ListGroup {
                    width: parent.width
                    ListItem {
                        visible: detail.live && ["sensor", "binary_sensor", "climate"].indexOf(app.domainOf(detail.live)) < 0
                        text: detail.live && app.isOn(detail.live) ? qsTr("Turn Off") : qsTr("Turn On")
                        iconName: "power"
                        onClicked: app.toggle(detail.live)
                    }
                    ListItem {
                        text: detail.live && app.pinned.indexOf(detail.live.entity_id) >= 0 ? qsTr("Remove from Favorites") : qsTr("Add to Favorites")
                        iconName: "star"
                        separator: false
                        onClicked: app.togglePin(detail.live)
                    }
                }
            }
        }
    }

    // ---- setup -------------------------------------------------------------------
    Component {
        id: setupPage
        Page {
            title: qsTr("Home Assistant")
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Enter the address of your Home Assistant (for example http://homeassistant.local:8123) and a long-lived access token: in Home Assistant open your profile › Security › Long-lived access tokens › Create token.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
            TextField { id: url; width: parent.width; placeholder: "http://homeassistant.local:8123"; text: app.server; inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase }
            TextField { id: tok; width: parent.width; placeholder: qsTr("Access token"); text: app.token; echoMode: TextInput.Password; inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText }
            Button {
                width: parent.width
                text: qsTr("Connect")
                enabled: url.text.trim() !== "" && tok.text.trim() !== ""
                onClicked: {
                    app.server = /^https?:\/\//.test(url.text.trim()) ? url.text.trim() : "http://" + url.text.trim()
                    app.token = tok.text.trim()
                    app.saveConfig()
                    app.refresh()
                    stack.pop()
                }
            }
            Button {
                visible: app.configured
                width: parent.width
                text: qsTr("Disconnect")
                primary: false
                destructive: true
                onClicked: {
                    app.server = ""; app.token = ""; app.entities = []; app.pinned = []
                    app.saveConfig()
                    stack.pop()
                }
            }
        }
    }
}
