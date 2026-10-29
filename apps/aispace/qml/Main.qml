// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Cloudy: the astraOS assistant, running a small language model on the
// phone (llama.cpp, started by astrad). The model is downloaded the first
// time, if you agree; after that Cloudy works without the internet and
// nothing you write leaves the phone. Cloudy can also act on the phone:
// open apps, start timers and alarms, add events, read the weather.
Rectangle {
    id: app
    color: Theme.background

    readonly property string configPath: Files.appData + "/cloudy.json"
    property string modelId: "light"
    property var conversations: []              // [{ id, title, messages, updated }]
    property int current: -1
    property bool busy: false
    property string streamingText: ""
    property string error: ""
    readonly property var conv: current >= 0 && current < conversations.length ? conversations[current] : null
    readonly property var engine: CloudyEngine.state
    readonly property var model: (engine.models || []).find(m => m.id === modelId) || null
    readonly property bool installed: !!model && !!model.installed
    readonly property bool downloading: !!engine.downloading
    readonly property bool ready: engine.ready === true && engine.running === modelId
    readonly property string endpoint: "http://127.0.0.1:" + (engine.port || 8742) + "/v1/chat/completions"

    function load() {
        try {
            const c = JSON.parse(Files.readText(configPath, 8 * 1024 * 1024) || "{}")
            modelId = c.model || "light"
            conversations = c.conversations || []
        } catch (e) {}
    }
    function save() {
        Files.writeText(configPath, JSON.stringify({ model: modelId, conversations: conversations.slice(0, 50) }))
    }
    function newConversation() {
        conversations = [{ id: Date.now(), title: qsTr("New Chat"), messages: [], updated: Date.now() }].concat(conversations)
        current = 0
        save()
    }
    function startEngine() {
        if (installed && engine.running !== modelId)
            CloudyEngine.call("start", { model: modelId }, (r, e) => { if (e) app.error = e })
    }
    onInstalledChanged: startEngine()
    Timer { interval: 60000; repeat: true; running: app.ready; onTriggered: CloudyEngine.call("keepAlive", {}, null) }

    // ---- tools Cloudy can use on the phone ---------------------------------
    function fn(name, description, props, required) {
        return { type: "function", function: { name: name, description: description,
                 parameters: { type: "object", properties: props, required: required || [] } } }
    }
    readonly property var allTools: [
        fn("open_app", "Open an app on the phone by its package name (see list_apps).", { package: { type: "string" } }, ["package"]),
        fn("list_apps", "List the installed apps with their package names.", {}),
        fn("start_timer", "Start a countdown timer.", { seconds: { type: "integer" }, label: { type: "string" } }, ["seconds"]),
        fn("set_alarm", "Set an alarm (24-hour time).", { hour: { type: "integer" }, minute: { type: "integer" }, label: { type: "string" } }, ["hour", "minute"]),
        fn("add_calendar_event", "Add a calendar event. Times are ISO 8601 local time.", { title: { type: "string" }, start: { type: "string" }, end: { type: "string" }, location: { type: "string" } }, ["title", "start"]),
        fn("get_weather", "The current weather and today's forecast here.", {}),
        fn("search_web", "Open a web search in Planet, the browser.", { query: { type: "string" } }, ["query"])
    ]
    // Settings › Cloudy can turn off web searches and actions on the phone.
    readonly property var tools: allTools.filter(t => (t.function.name !== "search_web" || Settings.values["cloudy.web"] !== false)
                                                   && (t.function.name === "search_web" || t.function.name === "get_weather" || Settings.values["cloudy.actions"] !== false))
    function runTool(name, input, done) {
        const isStr = (v) => typeof v === "string"
        const isInt = (v) => typeof v === "number" && Math.floor(v) === v
        switch (name) {
        case "list_apps":
            return done(JSON.stringify(Packages.list().filter(p => p.launcher).map(p => ({ name: p.name, package: p.package }))))
        case "open_app":
            if (!isStr(input.package)) return done("package must be a string")
            Packages.launch(input.package, {})
            return done("opened")
        case "start_timer":
            if (!isInt(input.seconds) || input.seconds <= 0) return done("seconds must be a positive integer")
            return Alarms.call("startTimer", { seconds: input.seconds, label: input.label || "" }, (r, e) => done(e || "timer started"))
        case "set_alarm":
            if (!isInt(input.hour) || !isInt(input.minute)) return done("hour and minute must be integers")
            return Alarms.call("set", { hour: input.hour, minute: input.minute, days: [], label: input.label || "", enabled: true }, (r, e) => done(e || "alarm set"))
        case "add_calendar_event": {
            const s = Date.parse(input.start), e = input.end ? Date.parse(input.end) : s + 3600000
            if (!isStr(input.title) || isNaN(s) || isNaN(e)) return done("title and valid start/end times are required")
            return Calendar.call("add", { title: input.title, start: s, end: e, location: input.location || "", alert: 15 }, (r, err) => done(err || "event added"))
        }
        case "get_weather":
            return done(Weather.available ? JSON.stringify(Weather.current) : "weather not available")
        case "search_web":
            if (!isStr(input.query)) return done("query must be a string")
            Packages.launch("com.astra.planet", { query: input.query })
            return done("opened in Planet")
        }
        done("unknown tool")
    }

    function systemPrompt() {
        return "You are Cloudy, the assistant built into astraOS, a phone operating system, running on the phone itself. "
             + (Settings.values["account.name"] ? "You talk with " + Settings.values["account.name"] + ". " : "")
             + "Answer in the user's language (the phone is set to " + Language.nameOf(Language.current) + "). "
             + "Keep answers short and friendly. When asked to do something on the phone, call a tool, then say briefly what you did. "
             + "It is " + new Date().toString() + "."
    }

    // ---- chat with the local model (OpenAI compatible), streamed --------------
    function send(text) {
        if (!text.trim() || busy || !ready)
            return
        if (!conv) newConversation()
        const c = conv
        c.messages.push({ role: "user", content: text.trim() })
        if (c.title === qsTr("New Chat")) c.title = text.trim().slice(0, 40)
        conversationsChanged()
        request()
    }
    function request() {
        const c = conv
        busy = true
        error = ""
        streamingText = ""
        let content = ""
        const calls = []           // by index: { id, name, args }
        let finish = ""
        let parsed = 0
        const xhr = new XMLHttpRequest()
        const consume = () => {
            const textSoFar = xhr.responseText || ""
            const end = textSoFar.lastIndexOf("\n\n")
            if (end < parsed) return
            const chunk = textSoFar.slice(parsed, end)
            parsed = end + 2
            for (const ev of chunk.split("\n\n")) {
                const line = ev.split("\n").find(l => l.startsWith("data: "))
                if (!line || line === "data: [DONE]") continue
                let d
                try { d = JSON.parse(line.slice(6)) } catch (e) { continue }
                const choice = (d.choices || [])[0]
                if (!choice) continue
                const delta = choice.delta || {}
                if (delta.content) { content += delta.content; app.streamingText = content }
                for (const t of (delta.tool_calls || [])) {
                    const k = t.index || 0
                    calls[k] = calls[k] || { id: "", name: "", args: "" }
                    if (t.id) calls[k].id = t.id
                    if (t.function && t.function.name) calls[k].name += t.function.name
                    if (t.function && t.function.arguments) calls[k].args += t.function.arguments
                }
                if (choice.finish_reason) finish = choice.finish_reason
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.LOADING) consume()
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) {
                app.error = xhr.status === 0 ? qsTr("Cloudy is starting, try again in a moment.") : qsTr("Cloudy couldn't answer (%1).").arg(xhr.status)
                app.busy = false
                app.startEngine()
                return
            }
            consume()
            app.finishTurn(c, content, calls.filter(x => x), finish)
        }
        xhr.open("POST", endpoint)
        xhr.setRequestHeader("content-type", "application/json")
        xhr.send(JSON.stringify({
            model: modelId,
            stream: true,
            temperature: 0.6,
            max_tokens: 1024,
            tools: tools,
            messages: [{ role: "system", content: systemPrompt() }].concat(c.messages)
        }))
    }
    function finishTurn(c, content, calls, finish) {
        const msg = { role: "assistant", content: content }
        if (calls.length)
            msg.tool_calls = calls.map((t, i) => ({ id: t.id || ("call_" + Date.now() + "_" + i), type: "function", function: { name: t.name, arguments: t.args || "{}" } }))
        c.messages.push(msg)
        c.updated = Date.now()
        streamingText = ""
        if (finish === "length")
            error = qsTr("The answer was too long and was cut off.")
        conversationsChanged()
        save()
        if (!calls.length) {
            busy = false
            return
        }
        // Run every tool, then send all the results back.
        let pending = msg.tool_calls.length
        for (const call of msg.tool_calls) {
            let input = {}
            let bad = false
            try { input = JSON.parse(call.function.arguments || "{}") } catch (e) { bad = true }
            const finishCall = (result) => {
                c.messages.push({ role: "tool", tool_call_id: call.id, content: String(result) })
                if (--pending === 0) app.request()
            }
            if (bad) finishCall("invalid JSON arguments: call the tool again")
            else app.runTool(call.function.name, input, finishCall)
        }
    }
    function textOf(m) { return typeof m.content === "string" ? m.content : "" }
    function toolsOf(m) { return (m.tool_calls || []).map(t => t.function.name) }

    Component.onCompleted: {
        load()
        if (conversations.length) current = 0
        startEngine()
    }

    // ---- UI ---------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.light ? "#EEE9FF" : "#120A24" }
            GradientStop { position: 0.5; color: Theme.background }
        }
    }

    Item {
        id: header
        y: Theme.statusBarHeight
        width: parent.width
        height: 56
        IconButton { x: 12; anchors.verticalCenter: parent.verticalCenter; iconName: "history"; size: 40; color: "transparent"; onClicked: chats.open() }
        Text {
            anchors.centerIn: parent
            text: "Cloudy"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.Bold
            color: Theme.text
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            IconButton { iconName: "edit"; size: 40; color: "transparent"; onClicked: app.newConversation() }
            IconButton { iconName: "settings"; size: 40; color: "transparent"; onClicked: settings.open() }
        }
    }

    // Welcome / setup
    Column {
        visible: !app.conv || app.conv.messages.length === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -60
        width: parent.width - 60
        spacing: 16
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "sparkles"; size: 64; color: "#9B6BFF" }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !app.engine.engine ? qsTr("Cloudy isn't available on this system yet.")
                : !app.installed ? qsTr("Meet Cloudy")
                : app.ready ? qsTr("Hi! What can I do for you?") : qsTr("Cloudy is waking up…")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            visible: !app.installed && !!app.engine.engine
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: qsTr("Cloudy runs on your phone: after a one-time download of about %1 it works without the internet, and what you write stays here.")
                  .arg(app.model ? Math.round(app.model.size / 1e6) + " MB" : "500 MB")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.footnoteSize + 1
            color: Theme.textSecondary
        }
        Column {
            visible: app.downloading
            width: parent.width
            spacing: 8
            ProgressBar { width: parent.width; value: app.engine.progress || 0 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Downloading… %1%").arg(Math.round((app.engine.progress || 0) * 100)); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            Button { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Cancel"); primary: false; onClicked: CloudyEngine.call("cancel", {}, null) }
        }
        Row {
            visible: !app.installed && !app.downloading && !!app.engine.engine
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Button { text: qsTr("Download"); onClicked: CloudyEngine.call("download", { model: app.modelId }, null) }
            Button { text: qsTr("Not Now"); primary: false; onClicked: Application.quit() }
        }
        Text { visible: !!app.engine.error; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: app.engine.error || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.danger }
        Flow {
            visible: app.ready
            width: parent.width
            spacing: 8
            Repeater {
                model: [qsTr("Set a timer for 10 minutes"), qsTr("What's the weather like today?"), qsTr("Plan my Saturday"), qsTr("Explain black holes simply")]
                delegate: Rectangle {
                    required property string modelData
                    width: chip.implicitWidth + 28
                    height: 38
                    radius: 19
                    color: Theme.surface
                    Text { id: chip; anchors.centerIn: parent; text: parent.modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.text }
                    MouseArea { anchors.fill: parent; onClicked: app.send(parent.modelData) }
                }
            }
        }
    }

    ListView {
        id: list
        anchors.top: header.bottom
        anchors.bottom: composer.top
        width: parent.width
        clip: true
        spacing: 10
        model: app.conv ? app.conv.messages.filter(m => typeof m.content === "string" || m.content.some(b => b.type === "text" || b.type === "tool_use")) : []
        onCountChanged: positionViewAtEnd()
        footer: Item {
            width: list.width
            height: (app.busy ? typing.height + 16 : 8) + (app.error ? err.height + 16 : 0)
            Rectangle {
                id: typing
                visible: app.busy
                x: 16
                width: Math.min(list.width - 80, streamText.implicitWidth + 32)
                height: streamText.height + 24
                radius: 22
                color: Theme.surface
                Text {
                    id: streamText
                    x: 16; y: 12
                    width: Math.min(list.width - 112, implicitWidth)
                    wrapMode: Text.WordWrap
                    textFormat: Text.MarkdownText
                    text: app.streamingText || "…"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.text
                    onTextChanged: list.positionViewAtEnd()
                }
            }
            Text {
                id: err
                visible: app.error !== ""
                y: app.busy ? typing.height + 16 : 8
                x: 16
                width: list.width - 32
                wrapMode: Text.WordWrap
                text: app.error
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.danger
            }
        }
        delegate: Item {
            required property var modelData
            readonly property bool mine: modelData.role === "user"
            readonly property string body: app.textOf(modelData)
            readonly property var used: app.toolsOf(modelData)
            width: list.width
            height: bubble.height + (usedText.visible ? usedText.height + 4 : 0)
            Text {
                id: usedText
                visible: parent.used.length > 0
                x: 20
                text: "⚡ " + parent.used.join(", ").replace(/_/g, " ")
                font.family: Theme.fontFamily
                font.pixelSize: 12
                color: Theme.textSecondary
            }
            Rectangle {
                id: bubble
                visible: parent.body !== ""
                y: usedText.visible ? usedText.height + 4 : 0
                x: parent.mine ? parent.width - width - 16 : 16
                width: Math.min(parent.width - 80, msg.implicitWidth + 32)
                height: visible ? msg.height + 24 : 0
                radius: 22
                color: parent.mine ? "#7C4DFF" : Theme.surface
                Text {
                    id: msg
                    x: 16; y: 12
                    width: Math.min(list.width - 112, implicitWidth)
                    wrapMode: Text.WordWrap
                    textFormat: parent.parent.mine ? Text.PlainText : Text.MarkdownText
                    text: parent.parent.body
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: parent.parent.mine ? "white" : Theme.text
                    onLinkActivated: (l) => Packages.launch("com.astra.planet", { url: l })
                }
            }
        }
    }

    Rectangle {
        id: composer
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64 + Theme.homeIndicatorHeight * 0.6
        color: "transparent"
        Rectangle {
            x: 14; y: 8
            width: parent.width - 28
            height: 48
            radius: 24
            color: Theme.surface
            border.width: 1
            border.color: Theme.separator
            TextInput {
                id: input
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 56
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
                clip: true
                enabled: app.ready
                EnterKey.type: Qt.EnterKeySend
                onAccepted: { app.send(text); text = "" }
                Text { anchors.fill: parent; verticalAlignment: Text.AlignVCenter; visible: !parent.text; text: qsTr("Ask Cloudy"); font: parent.font; color: Theme.textTertiary }
            }
            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                size: 38
                iconName: "arrow-up"
                color: input.text && !app.busy ? "#7C4DFF" : Theme.surfaceRaised
                onClicked: { app.send(input.text); input.text = "" }
            }
        }
    }

    // ---- chats ---------------------------------------------------------------------
    Sheet {
        id: chats
        Column {
            width: parent.width
            spacing: 10
            Text { text: qsTr("Chats"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            ListGroup {
                width: parent.width
                Repeater {
                    model: app.conversations
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.title
                        subtitle: Qt.locale().toString(new Date(modelData.updated), Locale.ShortFormat)
                        selected: index === app.current
                        onClicked: { app.current = index; chats.close() }
                        IconButton {
                            size: 32
                            iconName: "trash"
                            color: "transparent"
                            iconColor: Theme.danger
                            onClicked: {
                                const list = app.conversations.slice()
                                list.splice(index, 1)
                                app.conversations = list
                                app.current = list.length ? 0 : -1
                                app.save()
                            }
                        }
                    }
                }
                ListItem { visible: app.conversations.length === 0; text: qsTr("No chats yet"); enabled: false; separator: false }
            }
        }
    }

    // ---- settings ------------------------------------------------------------------
    Sheet {
        id: settings
        Column {
            width: parent.width
            spacing: 14
            Text { text: "Cloudy"; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Cloudy runs a small language model (Qwen 2.5) on this phone with llama.cpp. Your chats never leave the phone.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
            ListGroup {
                width: parent.width
                title: qsTr("Model")
                Repeater {
                    model: app.engine.models || []
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name
                        subtitle: Math.round(modelData.size / 1e6) + " MB" + (modelData.installed ? " • " + qsTr("Downloaded") : "")
                        selected: app.modelId === modelData.id
                        separator: index < (app.engine.models || []).length - 1
                        onClicked: {
                            app.modelId = modelData.id
                            app.save()
                            if (modelData.installed) app.startEngine()
                            else CloudyEngine.call("download", { model: modelData.id }, null)
                        }
                    }
                }
            }
            Button {
                width: parent.width
                text: qsTr("Delete Downloaded Model")
                primary: false
                destructive: true
                visible: app.installed
                onClicked: { CloudyEngine.call("remove", { model: app.modelId }, null); settings.close() }
            }
            Button {
                width: parent.width
                text: qsTr("Delete All Chats")
                primary: false
                destructive: true
                onClicked: { app.conversations = []; app.current = -1; app.save(); settings.close() }
            }
        }
    }
}
