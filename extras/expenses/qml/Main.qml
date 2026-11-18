// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Expenses: write down what you spend, by category, and see the month at a
// glance: the total, a bar per category, and the entries by day. Export the
// month as a CSV file in Documents.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/expenses.json"
    readonly property var categories: [
        { id: "food", name: qsTr("Food"), icon: "bag" }, { id: "transport", name: qsTr("Transport"), icon: "car" },
        { id: "home", name: qsTr("Home"), icon: "home" }, { id: "fun", name: qsTr("Fun"), icon: "gamepad" },
        { id: "health", name: qsTr("Health"), icon: "heart" }, { id: "shopping", name: qsTr("Shopping"), icon: "bag" },
        { id: "other", name: qsTr("Other"), icon: "more" }
    ]
    property var entries: []      // [{ id, amount (cents), cat, note, time }]
    property int nextId: 1
    property date month: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property string currency: "€"
    property int editing: 0
    property string cat: "food"
    property string amountText: ""
    property string exported: ""

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        entries = s.entries || []
        nextId = s.nextId || 1
        currency = s.currency || (Qt.locale().currencySymbol() || "€")
    }
    function save() { saveTimer.restart() }
    Timer { id: saveTimer; interval: 300; onTriggered: Files.writeText(app.storePath, JSON.stringify({ entries: app.entries, nextId: app.nextId, currency: app.currency })) }
    Component.onCompleted: load()

    function money(cents) { return (cents / 100).toLocaleString(Qt.locale(), "f", 2) + " " + currency }
    function inMonth(e) { const d = new Date(e.time); return d.getFullYear() === month.getFullYear() && d.getMonth() === month.getMonth() }
    readonly property var monthEntries: entries.filter(inMonth).sort((a, b) => b.time - a.time)
    readonly property int total: monthEntries.reduce((s, e) => s + e.amount, 0)
    readonly property var byCategory: {
        const sums = {}
        for (const e of monthEntries) sums[e.cat] = (sums[e.cat] || 0) + e.amount
        return categories.map(c => ({ cat: c, sum: sums[c.id] || 0 })).filter(x => x.sum > 0).sort((a, b) => b.sum - a.sum)
    }
    function shiftMonth(n) { month = new Date(month.getFullYear(), month.getMonth() + n, 1) }
    function parseAmount(t) { const v = Math.round(Number(String(t).replace(",", ".")) * 100); return isFinite(v) ? v : 0 }

    function openEditor(e) {
        editing = e ? e.id : 0
        cat = e ? e.cat : "food"
        amountText = e ? String(e.amount / 100) : ""
        amountField.text = amountText
        noteField.text = e ? e.note : ""
        sheet.open()
    }
    function commit() {
        const amount = parseAmount(amountField.text)
        if (amount <= 0) return
        if (editing)
            entries = entries.map(e => e.id === editing ? Object.assign({}, e, { amount: amount, cat: cat, note: noteField.text.trim() }) : e)
        else
            entries = entries.concat([{ id: nextId++, amount: amount, cat: cat, note: noteField.text.trim(), time: Date.now() }])
        save()
        sheet.close()
    }
    function exportCsv() {
        const lines = ["date,category,amount,note"]
        for (const e of monthEntries.slice().reverse())
            lines.push([new Date(e.time).toISOString().slice(0, 10), e.cat, (e.amount / 100).toFixed(2), '"' + e.note.replace(/"/g, '""') + '"'].join(","))
        const name = "Expenses-" + Qt.locale().toString(month, "yyyy-MM") + ".csv"
        Files.mkdir(Files.home, "Documents")
        exported = Files.writeText(Files.home + "/Documents/" + name, lines.join("\n")) ? qsTr("Saved Documents/%1").arg(name) : qsTr("Could not save the file")
    }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(mainPage) }

    Component {
        id: mainPage
        Page {
            title: qsTr("Expenses")
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: app.openEditor(null) }

            Row {
                width: parent.width
                IconButton { iconName: "chevron-left"; size: 38; onClicked: app.shiftMonth(-1) }
                Text { width: parent.width - 76; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: Qt.locale().toString(app.month, "MMMM yyyy"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                IconButton { iconName: "chevron-right"; size: 38; onClicked: app.shiftMonth(1) }
            }
            Card {
                accented: true
                Column {
                    width: parent.width
                    Text { text: qsTr("Spent this month"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.accentText; opacity: 0.85 }
                    Text { text: app.money(app.total); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize - 4; font.weight: Font.Bold; color: Theme.accentText }
                }
            }
            Card {
                visible: app.byCategory.length > 0
                Column {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: app.byCategory
                        delegate: Column {
                            required property var modelData
                            width: parent.width
                            spacing: 4
                            Row {
                                width: parent.width
                                Text { width: parent.width / 2; text: modelData.cat.name; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; color: Theme.text }
                                Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: app.money(modelData.sum); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; color: Theme.textSecondary }
                            }
                            ProgressBar { width: parent.width; height: 6; value: app.total ? modelData.sum / app.total : 0 }
                        }
                    }
                }
            }
            EmptyState {
                visible: app.monthEntries.length === 0
                width: parent.width
                iconName: "bag"
                title: qsTr("No expenses")
                message: qsTr("Tap + to write down what you spend.")
            }
            ListGroup {
                visible: app.monthEntries.length > 0
                title: qsTr("Entries")
                Repeater {
                    model: app.monthEntries
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        readonly property var c: app.categories.find(x => x.id === modelData.cat) || app.categories[6]
                        text: modelData.note || c.name
                        subtitle: c.name + "  ·  " + Qt.locale().toString(new Date(modelData.time), "ddd d MMM")
                        iconName: c.icon
                        iconTile: 32
                        separator: index < app.monthEntries.length - 1
                        Text { anchors.verticalCenter: parent.verticalCenter; text: app.money(modelData.amount); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                        onClicked: app.openEditor(modelData)
                    }
                }
            }
            Button {
                visible: app.monthEntries.length > 0
                width: parent.width
                primary: false
                iconName: "share"
                text: qsTr("Export this month (CSV)")
                onClicked: app.exportCsv()
            }
            Text { visible: app.exported !== ""; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: app.exported; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
        }
    }

    Sheet {
        id: sheet
        title: app.editing ? qsTr("Edit Expense") : qsTr("New Expense")
        Column {
            width: parent.width
            spacing: 12
            leftPadding: 18
            TextField { id: amountField; width: parent.width - 36; placeholder: qsTr("Amount"); inputMethodHints: Qt.ImhFormattedNumbersOnly; maximumLength: 10; onAccepted: app.commit() }
            TextField { id: noteField; width: parent.width - 36; placeholder: qsTr("Note (optional)"); maximumLength: 60 }
            Flow {
                width: parent.width - 36
                spacing: 8
                Repeater {
                    model: app.categories
                    delegate: Rectangle {
                        required property var modelData
                        width: chip.implicitWidth + 28; height: 36; radius: 18
                        color: app.cat === modelData.id ? Theme.accent : Theme.surfaceRaised
                        Text { id: chip; anchors.centerIn: parent; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; color: app.cat === modelData.id ? Theme.accentText : Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: app.cat = modelData.id }
                    }
                }
            }
            Button { width: parent.width - 36; text: app.editing ? qsTr("Save") : qsTr("Add"); enabled: app.parseAmount(amountField.text) > 0; onClicked: app.commit() }
            Button { visible: app.editing !== 0; width: parent.width - 36; destructive: true; text: qsTr("Delete Expense"); onClicked: { app.entries = app.entries.filter(e => e.id !== app.editing); app.save(); sheet.close() } }
        }
    }
}
