// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// AI Space: Cloudy, the astraOS assistant, powered by Claude (Anthropic
// Messages API). Answers stream in; Cloudy can also act on the phone with
// tools: open apps, start timers, add calendar events, read the weather.
// The API key stays in the app's private data.
Rectangle {
    id: app
    color: Theme.background

    readonly property string configPath: Files.appData + "/aispace.json"
    readonly property string model: "claude-opus-5-5"
    property string apiKey: ""
    property string effort: "medium"            // low | medium | high
    property var conversations: []              // [{ id, title, messages, updated }]
    property int current: -1
    property bool busy: false
    property string streamingText: ""
    property string error: ""
    readonly property var conv: current >= 0 && current < conversations.length ? conversations[current] : null

    function load() {
        try {
            const c = JSON.parse(Files.readText(configPath, 8 * 1024 * 1024) || "{}")
            apiKey = c.apiKey || ""
            effort = c.effort || "medium"
            conversations = c.conversations || []
        } catch (e) {}
    }
    function save() {
        Files.writeText(configPath, JSON.stringify({ apiKey: apiKey, effort: effort, conversations: conversations.slice(0, 50) }))
    }
    function newConversation() {
        conversations = [{ id: Date.now(), title: qsTr("New Chat"), messages: [], updated: Date.now() }].concat(conversations)
        current = 0
        save()
    }

    // ---- tools Cloudy can use on the phone ---------------------------------
    // Settings › Cloudy can turn off web searches and actions on the phone.
    readonly property var tools: allTools.filter(t => (t.name !== "search_web" || Settings.values["cloudy.web"] !== false)
                                                   && (t.name === "search_web" || t.name === "get_weather" || Settings.values["cloudy.actions"] !== false))
    readonly property var allTools: [
        { name: "open_app", description: "Open an app on the phone. Use the package from list_apps.", eager_input_streaming: true,
          input_schema: { type: "object", properties: { package: { type: "string" } }, required: ["package"], additionalProperties: false } },
        { name: "list_apps", description: "List the installed apps (name and package).", eager_input_streaming: true,
          input_schema: { type: "object", properties: {}, additionalProperties: false } },
        { name: "start_timer", description: "Start a countdown timer in Clock.", eager_input_streaming: true,
          input_schema: { type: "object", properties: { seconds: { type: "integer" }, label: { type: "string" } }, required: ["seconds"], additionalProperties: false } },
        { name: "set_alarm", description: "Set an alarm in Clock (24-hour time).", eager_input_streaming: true,
          input_schema: { type: "object", properties: { hour: { type: "integer" }, minute: { type: "integer" }, label: { type: "string" } }, required: ["hour", "minute"], additionalProperties: false } },
        { name: "add_calendar_event", description: "Add an event to the calendar. Times are ISO 8601 in the phone's local time.", eager_input_streaming: true,
          input_schema: { type: "object", properties: { title: { type: "string" }, start: { type: "string" }, end: { type: "string" }, location: { type: "string" } }, required: ["title", "start"], additionalProperties: false } },
        { name: "get_weather", description: "Current weather and today's forecast where the phone is.", eager_input_streaming: true,
          input_schema: { type: "object", properties: {}, additionalProperties: false } },
        { name: "search_web", description: "Open a web search in Planet, the browser, for the user to read.", eager_input_streaming: true,
          input_schema: { type: "object", properties: { query: { type: "string" } }, required: ["query"], additionalProperties: false } }
    ]
    function runTool(name, input, done) {
        const isStr = (v) => typeof v === "string"
        const isInt = (v) => typeof v === "number" && Math.floor(v) === v
        switch (name) {
        case "list_apps":
            return done(JSON.stringify(Packages.list().filter(p => p.launcher).map(p => ({ name: p.name, package: p.package }))))
        case "open_app":
            if (!isStr(input.package)) return done("package must be a string", true)
            Packages.launch(input.package, {})
            return done("opened")
        case "start_timer":
            if (!isInt(input.seconds) || input.seconds <= 0) return done("seconds must be a positive integer", true)
            return Alarms.call("startTimer", { seconds: input.seconds, label: input.label || "" }, (r, e) => done(e || "timer started", !!e))
        case "set_alarm":
            if (!isInt(input.hour) || !isInt(input.minute)) return done("hour and minute must be integers", true)
            return Alarms.call("set", { hour: input.hour, minute: input.minute, days: [], label: input.label || "", enabled: true }, (r, e) => done(e || "alarm set", !!e))
        case "add_calendar_event": {
            const s = Date.parse(input.start), e = input.end ? Date.parse(input.end) : s + 3600000
            if (!isStr(input.title) || isNaN(s) || isNaN(e)) return done("title and valid start/end times are required", true)
            return Calendar.call("add", { title: input.title, start: s, end: e, location: input.location || "", alert: 15 }, (r, err) => done(err || "event added", !!err))
        }
        case "get_weather":
            return done(Weather.available ? JSON.stringify(Weather.current) : "weather not available", !Weather.available)
        case "search_web":
            if (!isStr(input.query)) return done("query must be a string", true)
            Packages.launch("com.astra.planet", { query: input.query })
            return done("opened in Planet")
        }
        done("unknown tool", true)
    }

    function systemPrompt() {
        return "You are Cloudy, the assistant built into astraOS, a phone operating system. You talk with the owner of the phone"
             + (Settings.values["account.name"] ? " (" + Settings.values["account.name"] + ")" : "") + ". "
             + "Answer in the user's language (the phone is set to " + Language.nameOf(Language.current) + "). "
             + "Keep answers short and friendly, like a phone assistant; use lists only when they help. "
             + "When the user asks you to do something on the phone, use the tools; say briefly what you did. "
             + "It is " + new Date().toString() + "."
    }

    // ---- the Messages API, streamed ------------------------------------------
    function send(text) {
        if (!text.trim() || busy)
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
        const blocks = []        // the assistant content, rebuilt from the stream
        const partial = {}       // index -> accumulated input JSON of a tool_use
        let stop = ""
        let parsed = 0           // characters of responseText already handled
        const xhr = new XMLHttpRequest()
        const consume = () => {
            const textSoFar = xhr.responseText || ""
            const end = textSoFar.lastIndexOf("\n\n")
            if (end < parsed) return
            const chunk = textSoFar.slice(parsed, end)
            parsed = end + 2
            for (const ev of chunk.split("\n\n")) {
                const line = ev.split("\n").find(l => l.startsWith("data: "))
                if (!line) continue
                let d
                try { d = JSON.parse(line.slice(6)) } catch (e) { continue }
                if (d.type === "content_block_start") {
                    blocks[d.index] = JSON.parse(JSON.stringify(d.content_block))
                    if (blocks[d.index].type === "tool_use") partial[d.index] = ""
                } else if (d.type === "content_block_delta") {
                    const b = blocks[d.index]
                    if (d.delta.type === "text_delta") { b.text += d.delta.text; app.streamingText += d.delta.text }
                    else if (d.delta.type === "input_json_delta") partial[d.index] += d.delta.partial_json
                    else if (d.delta.type === "thinking_delta") b.thinking = (b.thinking || "") + d.delta.thinking
                    else if (d.delta.type === "signature_delta") b.signature = (b.signature || "") + d.delta.signature
                } else if (d.type === "message_delta") {
                    stop = d.delta.stop_reason || stop
                } else if (d.type === "error") {
                    app.error = d.error && d.error.message ? d.error.message : qsTr("Something went wrong")
                }
            }
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.LOADING) consume()
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) {
                let msg = qsTr("Cloudy is not reachable right now.")
                try { msg = JSON.parse(xhr.responseText).error.message } catch (e) {}
                if (xhr.status === 401) msg = qsTr("The API key was refused. Check it in AI Space settings.")
                app.error = msg
                app.busy = false
                return
            }
            consume()
            app.finishTurn(c, blocks.filter(b => b), partial, stop)
        }
        xhr.open("POST", "https://api.anthropic.com/v1/messages")
        xhr.setRequestHeader("content-type", "application/json")
        xhr.setRequestHeader("x-api-key", apiKey)
        xhr.setRequestHeader("anthropic-version", "2026-10-21")
        // Server-side fallback: a declined request is retried on another model.
        xhr.setRequestHeader("anthropic-beta", "server-side-fallback-2026-07-01")
        xhr.send(JSON.stringify({
            model: model,
            max_tokens: 64000,
            stream: true,
            system: systemPrompt(),
            output_config: { effort: effort },
            fallbacks: "default",
            tools: tools,
            messages: c.messages
        }))
    }
    function finishTurn(c, blocks, partial, stop) {
        // Tool inputs streamed eagerly: parse and validate them here.
        const calls = []
        for (let i = 0; i < blocks.length; i++) {
            const b = blocks[i]
            if (b.type !== "tool_use") continue
            const raw = partial[i] !== undefined ? partial[i] : ""
            try { b.input = raw ? JSON.parse(raw) : {}; calls.push({ block: b, ok: true }) }
            catch (e) { b.input = {}; calls.push({ block: b, ok: false }) }
        }
        c.messages.push({ role: "assistant", content: blocks })
        c.updated = Date.now()
        streamingText = ""
        if (stop === "refusal") {
            error = qsTr("Cloudy can't help with that request.")
        } else if (stop === "max_tokens" && calls.length) {
            error = qsTr("The answer was too long and was cut off.")
            calls.length = 0
        }
        conversationsChanged()
        save()
        if (stop !== "tool_use" || calls.length === 0) {
            busy = false
            return
        }
        // Run every tool, then answer them all in one user message.
        const results = []
        let pending = calls.length
        for (const call of calls) {
            const finish = (content, isError) => {
                results.push({ type: "tool_result", tool_use_id: call.block.id, content: String(content), is_error: !!isError })
                if (--pending === 0) {
                    c.messages.push({ role: "user", content: results })
                    app.request()
                }
            }
            if (!call.ok) finish("INVALID_JSON: the tool input was not valid JSON, call the tool again", true)
            else app.runTool(call.block.name, call.block.input, finish)
        }
    }
    function textOf(m) {
        if (typeof m.content === "string") return m.content
        return m.content.filter(b => b.type === "text").map(b => b.text).join("")
    }
    function toolsOf(m) {
        return typeof m.content === "string" ? [] : m.content.filter(b => b.type === "tool_use").map(b => b.name)
    }

    Component.onCompleted: {
        load()
        if (conversations.length) current = 0
        if (Application.args.prompt) send(Application.args.prompt)
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
            text: app.apiKey ? qsTr("Hi! What can I do for you?") : qsTr("Cloudy runs on Claude by Anthropic. Add your Anthropic API key to start.")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.titleSize
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Button { visible: !app.apiKey; anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Add API Key"); onClicked: settings.open() }
        Flow {
            visible: !!app.apiKey
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
                enabled: !!app.apiKey
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
        onOpenedChanged: if (opened) keyField.text = app.apiKey
        Column {
            width: parent.width
            spacing: 14
            Text { text: qsTr("AI Space"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: qsTr("Cloudy uses Claude (%1) through your own Anthropic API key. Create one at console.anthropic.com. Your chats go to Anthropic to be answered and are kept only on this phone.").arg(app.model)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textSecondary
            }
            TextField { id: keyField; width: parent.width; placeholder: "sk-ant-…"; echoMode: TextInput.Password; inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText }
            Text { text: qsTr("Thinking"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            SegmentedControl {
                width: parent.width
                model: [qsTr("Quick"), qsTr("Balanced"), qsTr("Deep")]
                currentIndex: ["low", "medium", "high"].indexOf(app.effort)
                onActivated: (i) => { app.effort = ["low", "medium", "high"][i]; app.save() }
            }
            Button {
                width: parent.width
                text: qsTr("Save")
                onClicked: { app.apiKey = keyField.text.trim(); app.save(); settings.close() }
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
