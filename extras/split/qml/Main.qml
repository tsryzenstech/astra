// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Split: the bill for a table. Add the amount and a tip, say how many are
// eating, and see what each one pays. Or add the people by name, give each
// one's own dishes, and share the rest.
Rectangle {
    id: app
    color: Theme.background

    readonly property string storePath: Files.appData + "/split.json"
    property string billText: ""
    property int tipPercent: 10
    property int people: 2
    property bool round: false           // round each share up to a whole unit
    property string currency: Qt.locale().currencySymbol() || "€"

    function load() {
        let s = {}
        try { s = JSON.parse(Files.readText(storePath) || "{}") } catch (e) { }
        tipPercent = s.tip !== undefined ? s.tip : 10
        people = s.people || 2
        round = !!s.round
    }
    function save() { Files.writeText(storePath, JSON.stringify({ tip: tipPercent, people: people, round: round })) }
    Component.onCompleted: load()

    readonly property real bill: Math.max(0, Number(billText.replace(",", ".")) || 0)
    readonly property real tip: bill * tipPercent / 100
    readonly property real total: bill + tip
    readonly property real each: {
        const e = total / Math.max(1, people)
        return round ? Math.ceil(e) : e
    }
    readonly property real collected: each * people
    function money(v) { return v.toLocaleString(Qt.locale(), "f", 2) + " " + currency }

    PageStack { id: stack; anchors.fill: parent; Component.onCompleted: open(mainPage) }

    Component {
        id: mainPage
        Page {
            title: qsTr("Split")
            Card {
                accented: true
                Column {
                    width: parent.width
                    spacing: 2
                    Text { text: qsTr("Each pays"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.accentText; opacity: 0.85 }
                    Text { text: app.money(app.each); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.accentText }
                    Text {
                        visible: app.bill > 0
                        text: qsTr("Total %1 · tip %2").arg(app.money(app.total)).arg(app.money(app.tip))
                        font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.accentText; opacity: 0.85
                    }
                }
            }
            TextField {
                width: parent.width
                placeholder: qsTr("Bill amount")
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                maximumLength: 10
                onTextChanged: app.billText = text
            }
            ListGroup {
                title: qsTr("Tip")
                Item {
                    width: parent.width
                    height: 118
                    Column {
                        x: 16
                        width: parent.width - 32
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        SegmentedControl {
                            width: parent.width
                            model: ["0%", "5%", "10%", "15%", "20%"]
                            currentIndex: [0, 5, 10, 15, 20].indexOf(app.tipPercent)
                            onActivated: (i) => { app.tipPercent = [0, 5, 10, 15, 20][i]; app.save() }
                        }
                        Row {
                            width: parent.width
                            Text { width: parent.width - 150; anchors.verticalCenter: parent.verticalCenter; text: qsTr("Custom: %1%").arg(app.tipPercent); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize - 1; color: Theme.textSecondary }
                            Slider { width: 150; anchors.verticalCenter: parent.verticalCenter; from: 0; to: 30; stepSize: 1; value: app.tipPercent; onMoved: { app.tipPercent = Math.round(value); app.save() } }
                        }
                    }
                }
            }
            ListGroup {
                title: qsTr("People")
                ListItem {
                    text: qsTr("Sharing the bill")
                    subtitle: qsTr("%n people", "", app.people)
                    Row {
                        spacing: 10
                        anchors.verticalCenter: parent.verticalCenter
                        IconButton { iconName: "minus"; size: 34; enabled: app.people > 1; onClicked: { app.people--; app.save() } }
                        IconButton { iconName: "plus"; size: 34; enabled: app.people < 40; onClicked: { app.people++; app.save() } }
                    }
                }
                ListItem {
                    text: qsTr("Round up each share")
                    subtitle: app.round && app.bill > 0 ? qsTr("%1 collected, %2 over").arg(app.money(app.collected)).arg(app.money(app.collected - app.total)) : ""
                    showSwitch: true
                    checked: app.round
                    separator: false
                    onToggled: (on) => { app.round = on; app.save() }
                }
            }
        }
    }
}
