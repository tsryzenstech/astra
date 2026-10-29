// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Planet: ask Cosmo. Answers come from the phone first (apps, weather,
// time, maths) and then from the web (Wikipedia, DuckDuckGo).
Rectangle {
    id: app
    color: "#05060C"

    property string query: ""
    property var cards: []          // [{ kind, title, text, source, url, icon, action }]
    property bool busy: false
    readonly property string historyKey: "app.com.astra.planet.history"
    readonly property var history: Settings.values[historyKey] || []

    function remember(q) {
        Settings.setValue(historyKey, [q].concat(history.filter(h => h !== q)).slice(0, 8))
    }
    function localAnswers(q) {
        const out = []
        const lower = q.toLowerCase()
        // Apps
        for (const p of Packages.list())
            if (p.launcher && p.name.toLowerCase().indexOf(lower) >= 0)
                out.push({ kind: "app", title: p.name, text: qsTr("Open the app"), icon: p.iconUrl, action: p.package })
        // Maths
        if (/^[0-9\s+\-*/().,%^]+$/.test(q) && /[0-9]/.test(q) && /[+\-*/^%]/.test(q)) {
            try {
                const v = Function('"use strict"; return (' + q.replace(/,/g, ".").replace(/\^/g, "**") + ")")()
                if (isFinite(v))
                    out.push({ kind: "math", title: String(Math.round(v * 1e10) / 1e10), text: q + " =" })
            } catch (e) {}
        }
        // Weather and time
        if (/weather|meteo|tempo|rain|pioggia|sun|sole|temperat/.test(lower) && Weather.available)
            out.push({ kind: "weather", title: Weather.current.temperature + "° " + Weather.current.city,
                       text: qsTr("H:%1° L:%2° • humidity %3%").arg(Weather.current.max).arg(Weather.current.min).arg(Weather.current.humidity),
                       action: "com.astra.weather" })
        if (/^(time|ora|what time|che ore)/.test(lower))
            out.push({ kind: "time", title: Qt.locale().toString(new Date(), "HH:mm"), text: Qt.locale().toString(new Date(), "dddd d MMMM yyyy") })
        return out
    }
    function ask(q) {
        q = q.trim()
        if (!q)
            return
        query = q
        remember(q)
        cards = localAnswers(q)
        busy = true
        let pending = 2
        const done = () => { if (--pending === 0) app.busy = false }
        // Wikipedia summary in the system language
        const lang = Language.current
        const wiki = new XMLHttpRequest()
        wiki.onreadystatechange = function() {
            if (wiki.readyState !== XMLHttpRequest.DONE)
                return
            try {
                const r = JSON.parse(wiki.responseText)
                const page = r.query && r.query.pages ? Object.values(r.query.pages)[0] : null
                if (page && page.extract)
                    app.cards = app.cards.concat([{ kind: "web", title: page.title, text: page.extract, source: "Wikipedia",
                                                    url: "https://" + lang + ".wikipedia.org/wiki/" + encodeURIComponent(page.title) }])
            } catch (e) {}
            done()
        }
        wiki.open("GET", "https://" + lang + ".wikipedia.org/w/api.php?action=query&format=json&prop=extracts&exintro=1&explaintext=1&redirects=1&generator=search&gsrlimit=1&gsrsearch=" + encodeURIComponent(q))
        wiki.send()
        // DuckDuckGo instant answer
        const ddg = new XMLHttpRequest()
        ddg.onreadystatechange = function() {
            if (ddg.readyState !== XMLHttpRequest.DONE)
                return
            try {
                const r = JSON.parse(ddg.responseText)
                if (r.Answer)
                    app.cards = [{ kind: "answer", title: String(r.Answer), text: r.AnswerType || "", source: "DuckDuckGo" }].concat(app.cards)
                else if (r.AbstractText && !app.cards.some(c => c.source === "Wikipedia"))
                    app.cards = app.cards.concat([{ kind: "web", title: r.Heading, text: r.AbstractText, source: r.AbstractSource, url: r.AbstractURL }])
                for (const t of (r.RelatedTopics || []).slice(0, 3))
                    if (t.Text)
                        app.cards = app.cards.concat([{ kind: "related", title: t.Text.split(" - ")[0], text: t.Text, source: "DuckDuckGo", url: t.FirstURL }])
            } catch (e) {}
            done()
        }
        ddg.open("GET", "https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&q=" + encodeURIComponent(q))
        ddg.send()
    }

    // Glow
    Rectangle {
        width: parent.width * 1.4
        height: width
        radius: width / 2
        x: -parent.width * 0.2
        y: -width * 0.55
        opacity: 0.35
        gradient: Gradient {
            GradientStop { position: 0; color: "#3B7BFF" }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.height + 120
        boundsBehavior: Flickable.DragOverBounds
        Column {
            id: column
            x: 16
            width: parent.width - 32
            topPadding: Theme.statusBarHeight + (app.query ? 20 : 120)
            spacing: 14
            Behavior on topPadding { SpringNumberAnimation { preset: Motion.smooth } }

            Column {
                visible: app.query === ""
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: 72
                    source: Qt.resolvedUrl("../icon.svg")
                }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Ask Cosmo"); font.family: Theme.fontFamily
                       font.pixelSize: 30; font.weight: Font.Bold; color: "white" }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Weather, maths, apps and anything on the web")
                       font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1; color: Theme.textSecondary }
            }

            Row {
                width: parent.width
                spacing: 8
                TextField {
                    id: field
                    width: parent.width - 56
                    radius: 24
                    placeholder: qsTr("Ask anything…")
                    onAccepted: app.ask(text)
                    Component.onCompleted: if (Application.args.mode === "search") focusInput()
                }
                IconButton { size: 48; iconName: "search"; color: Theme.accent; onClicked: app.ask(field.text) }
            }

            // History
            Flow {
                visible: app.query === "" && app.history.length > 0
                width: parent.width
                spacing: 8
                Repeater {
                    model: app.history
                    delegate: Rectangle {
                        required property string modelData
                        width: chip.implicitWidth + 24
                        height: 34
                        radius: 17
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Text { id: chip; anchors.centerIn: parent; text: modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize + 1; color: "white" }
                        MouseArea { anchors.fill: parent; onClicked: { field.text = modelData; app.ask(modelData) } }
                    }
                }
            }

            Spinner { visible: app.busy; running: app.busy; anchors.horizontalCenter: parent.horizontalCenter }

            Repeater {
                model: app.cards
                delegate: Card {
                    required property var modelData
                    accented: modelData.kind === "answer" || modelData.kind === "math" || modelData.kind === "weather" || modelData.kind === "time"
                    pressable: !!modelData.action
                    onClicked: Packages.launch(modelData.action)
                    Column {
                        width: parent.width
                        spacing: 6
                        Row {
                            spacing: 10
                            AppIcon { visible: modelData.kind === "app"; size: 36; source: modelData.icon || "" }
                            Text {
                                width: column.width - 80
                                text: modelData.title || ""
                                wrapMode: Text.Wrap
                                font.family: Theme.fontFamily
                                font.pixelSize: modelData.kind === "math" || modelData.kind === "time" ? 40 : Theme.headlineSize + 1
                                font.weight: Font.DemiBold
                                color: "white"
                            }
                        }
                        Text {
                            visible: !!modelData.text
                            width: parent.width
                            text: modelData.text || ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 8
                            elide: Text.ElideRight
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            color: Qt.rgba(1, 1, 1, 0.85)
                            lineHeight: 1.1
                        }
                        Text {
                            visible: !!modelData.source
                            text: modelData.source || ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.footnoteSize + 1
                            color: Theme.textTertiary
                        }
                    }
                }
            }

            Text {
                visible: app.query !== "" && !app.busy && app.cards.length === 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: qsTr("Cosmo found nothing for “%1”. Check the connection or try other words.").arg(app.query)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.textSecondary
            }
        }
    }
}
