// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Flashcards: decks of questions and answers, studied with spaced repetition
// (Leitner boxes): a card you know comes back later, one you miss comes back soon.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/cards.json"
    readonly property var intervals: [0, 1, 2, 4, 8, 16]      // days before a card of that box is due again
    property var decks: []        // [{ id, name, cards: [{ id, q, a, box, due }] }]
    property int nextId: 1
    property int deckId: 0        // deck being studied or edited
    property var queue: []        // card ids of the session
    property int at: 0
    property bool flipped: false
    property int knew: 0
    property int missed: 0
    property int editingCard: 0

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        decks = s.decks || []
        nextId = s.nextId || 1
    }
    function save() { saveTimer.restart() }
    Timer { id: saveTimer; interval: 300; onTriggered: Files.writeText(app.storePath, JSON.stringify({ decks: app.decks, nextId: app.nextId })) }
    Component.onCompleted: load()

    function deck(id) { return decks.find(d => d.id === id) || { id: 0, name: "", cards: [] } }
    function dueCards(d) { const now = Date.now(); return d.cards.filter(c => c.due <= now) }
    function updateDeck(id, fn) { decks = decks.map(d => d.id === id ? fn(d) : d); save() }
    function study(id) {
        deckId = id
        queue = dueCards(deck(id)).map(c => c.id).sort(() => Math.random() - 0.5)
        at = 0; flipped = false; knew = 0; missed = 0
        stack.open(studyPage)
    }
    function grade(good) {
        const id = queue[at]
        updateDeck(deckId, d => Object.assign({}, d, { cards: d.cards.map(c => {
            if (c.id !== id) return c
            const box = good ? Math.min(5, c.box + 1) : 0
            return Object.assign({}, c, { box: box, due: good ? Date.now() + intervals[box] * 86400000 : Date.now() + 60000 })
        }) }))
        good ? knew++ : missed++
        flipped = false
        at++
    }
    function addDeck() {
        const name = deckField.text.trim()
        if (!name) return
        decks = decks.concat([{ id: nextId++, name: name, cards: [] }])
        save()
        deckSheet.close()
    }
    function openCard(c) {
        editingCard = c ? c.id : 0
        qField.text = c ? c.q : ""
        aField.text = c ? c.a : ""
        cardSheet.open()
    }
    function commitCard() {
        const q = qField.text.trim(), a = aField.text.trim()
        if (!q || !a) return
        updateDeck(deckId, d => Object.assign({}, d, { cards: editingCard
            ? d.cards.map(c => c.id === editingCard ? Object.assign({}, c, { q: q, a: a }) : c)
            : d.cards.concat([{ id: nextId++, q: q, a: a, box: 0, due: 0 }]) }))
        cardSheet.close()
    }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(decksPage) }

    Component {
        id: decksPage
        Page {
            title: qsTr("Flashcards")
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: { deckField.text = ""; deckSheet.open() } }
            EmptyState {
                visible: app.decks.length === 0
                width: parent.width
                iconName: "layers"
                title: qsTr("No decks")
                message: qsTr("Make a deck for what you want to learn, then add cards to it.")
            }
            Repeater {
                model: app.decks
                delegate: Card {
                    id: dc
                    required property var modelData
                    readonly property int due: app.dueCards(modelData).length
                    pressable: true
                    padding: 16
                    onClicked: { app.deckId = modelData.id; stack.open(deckPage) }
                    Row {
                        width: parent.width
                        Column {
                            width: parent.width - 100
                            Text { width: parent.width; text: dc.modelData.name; elide: Text.ElideRight; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                            Text { text: qsTr("%n cards", "", dc.modelData.cards.length); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary }
                        }
                        Rectangle {
                            visible: dc.due > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: dueText.implicitWidth + 24; height: 32; radius: 16
                            color: Theme.accent
                            Text { id: dueText; anchors.centerIn: parent; text: qsTr("%1 due").arg(dc.due); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; font.weight: Font.DemiBold; color: Theme.accentText }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: deckPage
        Page {
            id: dp
            readonly property var d: app.deck(app.deckId)
            title: d.name
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: app.openCard(null) }
            Button {
                width: parent.width
                iconName: "play"
                text: dp.d.cards.length === 0 ? qsTr("Add cards to study") : app.dueCards(dp.d).length ? qsTr("Study %n cards", "", app.dueCards(dp.d).length) : qsTr("All caught up")
                enabled: app.dueCards(dp.d).length > 0
                onClicked: app.study(dp.d.id)
            }
            ListGroup {
                visible: dp.d.cards.length > 0
                Repeater {
                    model: dp.d.cards
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.q
                        subtitle: modelData.a
                        value: qsTr("Box %1").arg(modelData.box + 1)
                        separator: index < dp.d.cards.length - 1
                        onClicked: app.openCard(modelData)
                    }
                }
            }
            Button {
                width: parent.width
                destructive: true
                text: qsTr("Delete Deck")
                onClicked: Dialogs.show({ title: qsTr("Delete this deck?"), message: qsTr("Its cards are deleted too."),
                                          buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" }] },
                                        function(a) { if (a === "delete") { app.decks = app.decks.filter(x => x.id !== dp.d.id); app.save(); stack.pop() } })
            }
        }
    }

    Component {
        id: studyPage
        Page {
            id: sp
            readonly property var card: app.at < app.queue.length ? app.deck(app.deckId).cards.find(c => c.id === app.queue[app.at]) : null
            title: app.deck(app.deckId).name
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: sp.card ? qsTr("%1 of %2").arg(app.at + 1).arg(app.queue.length) : ""
                font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textSecondary
            }
            Card {
                visible: sp.card !== null
                pressable: true
                height: 280
                onClicked: app.flipped = !app.flipped
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    spacing: 14
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: app.flipped ? qsTr("Answer") : qsTr("Question"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; font.weight: Font.DemiBold; color: Theme.accent }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: sp.card ? (app.flipped ? sp.card.a : sp.card.q) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; color: Theme.text }
                    Text { visible: !app.flipped; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("Tap to see the answer"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.textTertiary }
                }
            }
            Row {
                visible: sp.card !== null && app.flipped
                width: parent.width
                spacing: 12
                Button { width: (parent.width - 12) / 2; destructive: true; text: qsTr("Again"); onClicked: app.grade(false) }
                Button { width: (parent.width - 12) / 2; text: qsTr("I knew it"); onClicked: app.grade(true) }
            }
            EmptyState {
                visible: sp.card === null
                width: parent.width
                iconName: "check-circle"
                title: qsTr("Session done")
                message: qsTr("%1 known, %2 to see again.").arg(app.knew).arg(app.missed)
            }
            Button { visible: sp.card === null; width: parent.width; text: qsTr("Done"); onClicked: stack.pop() }
        }
    }

    Sheet {
        id: deckSheet
        title: qsTr("New Deck")
        Column {
            width: parent.width
            spacing: 12
            leftPadding: 18
            TextField { id: deckField; width: parent.width - 36; placeholder: qsTr("Name of the deck"); maximumLength: 50; onAccepted: app.addDeck() }
            Button { width: parent.width - 36; text: qsTr("Add"); enabled: deckField.text.trim() !== ""; onClicked: app.addDeck() }
        }
    }
    Sheet {
        id: cardSheet
        title: app.editingCard ? qsTr("Edit Card") : qsTr("New Card")
        Column {
            width: parent.width
            spacing: 12
            leftPadding: 18
            TextField { id: qField; width: parent.width - 36; placeholder: qsTr("Question"); maximumLength: 200 }
            TextField { id: aField; width: parent.width - 36; placeholder: qsTr("Answer"); maximumLength: 300; onAccepted: app.commitCard() }
            Button { width: parent.width - 36; text: app.editingCard ? qsTr("Save") : qsTr("Add"); enabled: qField.text.trim() !== "" && aField.text.trim() !== ""; onClicked: app.commitCard() }
            Button {
                visible: app.editingCard !== 0
                width: parent.width - 36
                destructive: true
                text: qsTr("Delete Card")
                onClicked: { app.updateDeck(app.deckId, d => Object.assign({}, d, { cards: d.cards.filter(c => c.id !== app.editingCard) })); cardSheet.close() }
            }
        }
    }
}
