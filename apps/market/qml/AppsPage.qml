// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Apps: categories as chips, then the apps of the chosen one.
Flickable {
    id: page
    required property var store
    property string category: ""
    readonly property var categories: [...new Set(store.catalog.map(e => e.category))].sort()
    readonly property var list: store.catalog.filter(e => !category || e.category === category)
    contentHeight: column.height + 40

    Column {
        id: column
        x: 20
        y: Theme.statusBarHeight + 16
        width: parent.width - 40
        spacing: 16
        Text { text: qsTr("Apps"); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
        Flow {
            width: parent.width
            spacing: 8
            Repeater {
                model: [""].concat(page.categories)
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool on: page.category === modelData
                    width: label.implicitWidth + 28
                    height: 36
                    radius: 18
                    color: on ? Theme.accent : Theme.surface
                    Text { id: label; anchors.centerIn: parent; text: parent.modelData || qsTr("All"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; font.weight: Font.DemiBold; color: parent.on ? "white" : Theme.text }
                    MouseArea { anchors.fill: parent; onClicked: page.category = parent.modelData }
                }
            }
        }
        EmptyState { visible: page.list.length === 0 && !page.store.loading; iconName: "bag"; title: qsTr("No Apps"); message: page.store.error }
        Repeater {
            model: page.list
            delegate: AppRow { required property var modelData; store: page.store; entry: modelData }
        }
    }
}
