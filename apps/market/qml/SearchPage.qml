// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Search: by name, summary, category or package; suggestions when empty.
Flickable {
    id: page
    required property var store
    readonly property string q: field.text.trim().toLowerCase()
    readonly property var results: q ? store.catalog.filter(e => (e.name + " " + e.summary + " " + e.category + " " + e.package).toLowerCase().indexOf(q) >= 0) : []
    contentHeight: column.height + 40

    Column {
        id: column
        x: 20
        y: Theme.statusBarHeight + 16
        width: parent.width - 40
        spacing: 16
        Text { text: qsTr("Search"); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
        TextField { id: field; width: parent.width; placeholder: qsTr("Games, apps and more") }
        Column {
            visible: page.q === ""
            width: parent.width
            spacing: 6
            Text { text: qsTr("Discover"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text }
            Repeater {
                model: page.store.catalog.slice(0, 6)
                delegate: Text {
                    required property var modelData
                    text: "🔍  " + modelData.name
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize + 1
                    color: Theme.accent
                    topPadding: 6
                    MouseArea { anchors.fill: parent; onClicked: field.text = parent.modelData.name }
                }
            }
        }
        EmptyState { visible: page.q !== "" && page.results.length === 0; iconName: "search"; title: qsTr("No Results"); message: qsTr("Try another word.") }
        Repeater {
            model: page.results
            delegate: AppRow { required property var modelData; store: page.store; entry: modelData }
        }
    }
}
