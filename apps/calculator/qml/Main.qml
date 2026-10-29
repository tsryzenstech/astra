// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Calculator: basic keypad, scientific functions, history. Swipe the
// display sideways to delete the last digit, hold it to copy the result.
Rectangle {
    id: app
    color: "#000000"

    property string expr: ""          // what was typed, e.g. "12+3×(4"
    property string result: ""        // live preview of the result
    property bool justEvaluated: false
    property bool scientific: !!Settings.values["app.com.astra.calculator.scientific"]
    property bool degrees: Settings.values["app.com.astra.calculator.degrees"] !== false
    property var history: Settings.values["app.com.astra.calculator.history"] || []
    property real memory: 0

    function format(v) {
        if (!isFinite(v))
            return qsTr("Error")
        if (Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-9 && v !== 0))
            return v.toExponential(8).replace(/\.?0+e/, "e")
        const s = String(Math.round(v * 1e10) / 1e10)
        const parts = s.split(".")
        const loc = Qt.locale()
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, loc.groupSeparator || ",")
        return parts.join(loc.decimalPoint)
    }

    // ---- evaluation: shunting-yard over the typed expression --------------
    function evaluate(text) {
        const toks = []
        const src = text.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-")
        let i = 0
        while (i < src.length) {
            const c = src[i]
            if (/[0-9.]/.test(c)) {
                let j = i
                while (j < src.length && /[0-9.eE]/.test(src[j]) && !(/[eE]/.test(src[j]) && !/[0-9]/.test(src[j + 1] || "") && src[j + 1] !== "-")) j++
                toks.push({ t: "n", v: parseFloat(src.slice(i, j)) })
                i = j
                continue
            }
            const fn = /^(sin|cos|tan|asin|acos|atan|ln|log|√|sqrt)/.exec(src.slice(i))
            if (fn) { toks.push({ t: "f", v: fn[1] === "sqrt" ? "√" : fn[1] }); i += fn[1].length; continue }
            if (c === "π") { toks.push({ t: "n", v: Math.PI }); i++; continue }
            if (c === "e") { toks.push({ t: "n", v: Math.E }); i++; continue }
            if ("+-*/^%!()".indexOf(c) >= 0) { toks.push({ t: "o", v: c }); i++; continue }
            i++
        }
        // implicit multiplication: 2π, 3(4), )(
        const t2 = []
        for (let k = 0; k < toks.length; k++) {
            const a = t2[t2.length - 1], b = toks[k]
            if (a && ((a.t === "n" || (a.t === "o" && (a.v === ")" || a.v === "!" || a.v === "%"))) &&
                      (b.t === "n" || b.t === "f" || (b.t === "o" && b.v === "("))))
                t2.push({ t: "o", v: "*" })
            t2.push(b)
        }
        const prec = { "+": 1, "-": 1, "*": 2, "/": 2, "^": 4, "neg": 3 }
        const out = [], ops = []
        let prev = null
        for (const tk of t2) {
            if (tk.t === "n") out.push(tk)
            else if (tk.t === "f") ops.push(tk)
            else if (tk.v === "(") ops.push(tk)
            else if (tk.v === ")") {
                while (ops.length && ops[ops.length - 1].v !== "(") out.push(ops.pop())
                ops.pop()
                if (ops.length && ops[ops.length - 1].t === "f") out.push(ops.pop())
            } else if (tk.v === "!" || tk.v === "%") out.push(tk)
            else {
                let op = tk.v
                if (op === "-" && (!prev || (prev.t === "o" && "()!%".indexOf(prev.v) < 0) || prev.t === "f"))
                    op = "neg"
                while (ops.length) {
                    const top = ops[ops.length - 1]
                    if (top.t === "f" || (top.v !== "(" && (prec[top.v] > prec[op] || (prec[top.v] === prec[op] && op !== "^" && op !== "neg"))))
                        out.push(ops.pop())
                    else break
                }
                ops.push({ t: "o", v: op })
            }
            prev = tk
        }
        while (ops.length) { const o = ops.pop(); if (o.v !== "(") out.push(o) }
        const st = []
        const rad = (x) => app.degrees ? x * Math.PI / 180 : x
        const deg = (x) => app.degrees ? x * 180 / Math.PI : x
        const fact = (n) => { if (n < 0 || n > 170 || n % 1) return NaN; let r = 1; for (let k = 2; k <= n; k++) r *= k; return r }
        for (const tk of out) {
            if (tk.t === "n") { st.push(tk.v); continue }
            if (tk.t === "f") {
                const x = st.pop()
                st.push({ sin: Math.sin(rad(x)), cos: Math.cos(rad(x)), tan: Math.tan(rad(x)), asin: deg(Math.asin(x)),
                          acos: deg(Math.acos(x)), atan: deg(Math.atan(x)), ln: Math.log(x), log: Math.log10(x), "√": Math.sqrt(x) }[tk.v])
                continue
            }
            if (tk.v === "neg") { st.push(-st.pop()); continue }
            if (tk.v === "!") { st.push(fact(st.pop())); continue }
            if (tk.v === "%") { st.push(st.pop() / 100); continue }
            const b = st.pop(), a = st.pop()
            if (a === undefined || b === undefined) return NaN
            st.push(tk.v === "+" ? a + b : tk.v === "-" ? a - b : tk.v === "*" ? a * b : tk.v === "/" ? a / b : Math.pow(a, b))
        }
        return st.length === 1 ? st[0] : NaN
    }
    function balanced(text) {
        let open = 0
        for (const c of text) { if (c === "(") open++; else if (c === ")") open-- }
        return text + ")".repeat(Math.max(0, open))
    }
    function refresh() {
        const v = evaluate(balanced(expr))
        result = expr && isFinite(v) && /[^0-9.]/.test(expr) ? format(v) : ""
    }
    onExprChanged: refresh()
    onDegreesChanged: refresh()

    function press(k) {
        const last = expr.slice(-1)
        const isOp = (c) => "+−×÷^".indexOf(c) >= 0
        if (justEvaluated && /[0-9.πe(]|sin|cos|tan|ln|log|√/.test(k))
            expr = ""
        justEvaluated = false
        switch (k) {
        case "AC": expr = ""; return
        case "⌫": expr = expr.replace(/(sin|cos|tan|asin|acos|atan|ln|log)\($|.$/, ""); return
        case "=": {
            const full = balanced(expr)
            const v = evaluate(full)
            if (!expr || !isFinite(v)) { if (expr) result = qsTr("Error"); return }
            history = [{ expr: full, value: format(v) }].concat(history).slice(0, 60)
            Settings.setValue("app.com.astra.calculator.history", history)
            expr = String(Math.round(v * 1e12) / 1e12)
            result = ""
            justEvaluated = true
            return
        }
        case "±": {
            const m = /(-?)([0-9.]+)$/.exec(expr)
            if (m) expr = expr.slice(0, m.index) + (m[1] ? "" : "-") + m[2]
            else expr = "-" + expr
            return
        }
        case ".": {
            const m = /[0-9.]*$/.exec(expr)[0]
            if (m.indexOf(".") < 0) expr += m === "" ? "0." : "."
            return
        }
        case "x²": expr += "^2"; return
        case "xʸ": expr += "^"; return
        case "1/x": expr = "1÷(" + expr + ")"; return
        case "x!": expr += "!"; return
        case "√": case "sin": case "cos": case "tan": case "ln": case "log": case "asin": case "acos": case "atan":
            expr += k + "("; return
        case "mc": memory = 0; return
        case "m+": memory += evaluate(balanced(expr)) || 0; return
        case "m−": memory -= evaluate(balanced(expr)) || 0; return
        case "mr": expr += String(memory); return
        case "Rad": case "Deg":
            degrees = !degrees
            Settings.setValue("app.com.astra.calculator.degrees", degrees)
            return
        }
        if (isOp(k)) {
            if (expr === "" && k !== "−") expr = "0"
            if (isOp(last)) expr = expr.slice(0, -1)
            expr += k
            return
        }
        expr += k
    }

    // ---- display ---------------------------------------------------------
    Item {
        id: display
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: pad.top
        anchors.margins: 22

        Row {
            y: Theme.statusBarHeight
            spacing: 14
            IconButton {
                iconName: "history"
                size: 40
                color: "#1C1C1E"
                onClicked: historySheet.open()
            }
            IconButton {
                iconName: "calculator"
                size: 40
                color: app.scientific ? Theme.accent : "#1C1C1E"
                onClicked: {
                    app.scientific = !app.scientific
                    Settings.setValue("app.com.astra.calculator.scientific", app.scientific)
                }
            }
            Text {
                visible: app.scientific
                anchors.verticalCenter: parent.verticalCenter
                text: app.degrees ? "Deg" : "Rad"
                font.family: Theme.fontFamily
                font.pixelSize: 15
                color: "#8E8E93"
            }
        }

        Text {
            id: exprText
            anchors.right: parent.right
            anchors.bottom: resultText.top
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: app.expr.replace(/\./g, Qt.locale().decimalPoint) || "0"
            elide: Text.ElideLeft
            font.family: Theme.fontFamily
            font.pixelSize: app.result ? 34 : Math.max(38, Math.min(92, 92 * 9 / Math.max(9, text.length)))
            font.weight: Font.Light
            color: app.result ? "#8E8E93" : "white"
            Behavior on font.pixelSize { SpringNumberAnimation { preset: Motion.snappy } }
        }
        Text {
            id: resultText
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: app.result
            visible: text !== ""
            height: visible ? implicitHeight : 0
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 30
            font.family: Theme.fontFamily
            font.pixelSize: 80
            font.weight: Font.Light
            color: "white"
        }
        MouseArea {
            anchors.fill: parent
            anchors.topMargin: Theme.statusBarHeight + 50
            property real startX
            onPressed: (m) => startX = m.x
            onReleased: (m) => { if (Math.abs(m.x - startX) > 40) app.press("⌫") }
            onPressAndHold: {
                copyHelper.text = app.result || app.expr
                copyHelper.selectAll()
                copyHelper.copy()
                toast.opacity = 1
                toastTimer.restart()
            }
        }
        TextEdit { id: copyHelper; visible: false }
        Rectangle {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.statusBarHeight + 60
            width: 90; height: 34; radius: 17
            color: "#3A3A3C"
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { anchors.centerIn: parent; text: qsTr("Copied"); color: "white"; font.family: Theme.fontFamily; font.pixelSize: 14 }
            Timer { id: toastTimer; interval: 1200; onTriggered: toast.opacity = 0 }
        }
    }

    // ---- keypad ------------------------------------------------------------
    readonly property var sciKeys: [
        ["(", ")", "mc", "m+", "m−", "mr"],
        ["x²", "xʸ", "√", "1/x", "x!", app.degrees ? "Rad" : "Deg"],
        ["sin", "cos", "tan", "ln", "log", "π"],
        ["asin", "acos", "atan", "e", "%", "⌫"]
    ]
    readonly property var keys: [
        [app.expr === "" ? "AC" : "⌫", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="]
    ]

    Column {
        id: pad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.homeIndicatorHeight + 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 32
        spacing: 12
        readonly property real key: (width - 3 * 14) / 4

        Grid {
            visible: app.scientific
            columns: 6
            spacing: 8
            Repeater {
                model: [].concat.apply([], app.sciKeys)
                delegate: Key {
                    required property string modelData
                    label: modelData
                    width: (pad.width - 5 * 8) / 6
                    height: 40
                    fontSize: 16
                    face: "#1C1C1E"
                    active: modelData === "mr" && app.memory !== 0
                }
            }
        }

        Repeater {
            model: app.keys
            delegate: Row {
                required property var modelData
                spacing: 14
                Repeater {
                    model: modelData
                    delegate: Key {
                        required property string modelData
                        label: modelData
                        width: modelData === "0" ? pad.key * 2 + 14 : pad.key
                        height: app.scientific ? pad.key * 0.78 : pad.key
                        face: "+−×÷=".indexOf(modelData) >= 0 ? Theme.accent
                            : ["AC", "⌫", "±", "%"].indexOf(modelData) >= 0 ? "#5C5C5F" : "#2C2C2E"
                        alignLeft: modelData === "0"
                    }
                }
            }
        }
    }

    component Key: Rectangle {
        id: key
        property string label
        property color face
        property real fontSize: 34
        property bool alignLeft: false
        property bool active: false
        radius: height / 2
        color: area.pressed ? Qt.lighter(face, 1.45) : active ? Qt.lighter(face, 1.3) : face
        Behavior on color { ColorAnimation { duration: area.pressed ? 0 : 260 } }
        scale: area.pressed ? 0.96 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }
        Text {
            visible: key.label !== "⌫"
            anchors.verticalCenter: parent.verticalCenter
            x: key.alignLeft ? key.height * 0.38 : (parent.width - width) / 2
            text: key.label === "." ? Qt.locale().decimalPoint : key.label
            font.family: Theme.fontFamily
            font.pixelSize: key.fontSize
            color: "white"
        }
        Icon {
            visible: key.label === "⌫"
            anchors.centerIn: parent
            name: "backspace"
            size: key.fontSize * 0.8
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onClicked: app.press(key.label)
        }
    }

    // ---- history ------------------------------------------------------------
    Rectangle {
        id: historySheet
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.9)
        visible: reveal.value > 0.01
        opacity: reveal.value
        Spring { id: reveal; to: 0; response: 0.34; dampingFraction: 1 }
        function open() { reveal.animateTo(1, 0) }
        function close() { reveal.animateTo(0, 0) }
        MouseArea { anchors.fill: parent; onClicked: historySheet.close() }
        Column {
            x: 20
            y: Theme.statusBarHeight + 12
            width: parent.width - 40
            spacing: 12
            Item {
                width: parent.width
                height: 40
                Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("History"); font.family: Theme.fontFamily; font.pixelSize: 28; font.weight: Font.Bold; color: "white" }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: app.history.length > 0
                    text: qsTr("Clear")
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    color: Theme.accent
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: { app.history = []; Settings.setValue("app.com.astra.calculator.history", []) } }
                }
            }
            Text {
                visible: app.history.length === 0
                text: qsTr("Your calculations show up here.")
                font.family: Theme.fontFamily
                font.pixelSize: 16
                color: "#8E8E93"
            }
            ListView {
                width: parent.width
                height: historySheet.height - y - 140
                clip: true
                spacing: 4
                model: app.history
                delegate: Item {
                    required property var modelData
                    width: ListView.view.width
                    height: 64
                    Column {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Text { anchors.right: parent.right; text: modelData.expr; color: "#8E8E93"; font.family: Theme.fontFamily; font.pixelSize: 15 }
                        Text { anchors.right: parent.right; text: "= " + modelData.value; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 24 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            app.expr = modelData.value.replace(new RegExp("\\" + (Qt.locale().groupSeparator || ","), "g"), "").replace(Qt.locale().decimalPoint, ".")
                            app.justEvaluated = true
                            historySheet.close()
                        }
                    }
                }
            }
        }
    }
}
