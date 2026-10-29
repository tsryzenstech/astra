// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Updates: apps with a newer version on Market, and the apps you got here.
Flickable {
    id: page
    required property var store
    readonly property var fromMarket: store.installed.filter(p => p.installer === "com.astra.market")
    contentHeight: column.height + 40

    Column {
        id: column
        x: 20
        y: Theme.statusBarHeight + 16
        width: parent.width - 40
        spacing: 16
        Item {
            width: parent.width
            height: title.height
            Text { id: title; text: qsTr("Updates"); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
            Text {
                visible: page.store.updates.length > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                text: qsTr("Update All")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.accent
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: page.store.updateAll() }
            }
        }
        EmptyState {
            visible: page.store.updates.length === 0
            iconName: "check-circle"
            title: qsTr("All Apps Up to Date")
            message: page.store.loading ? qsTr("Checking…") : ""
        }
        Repeater {
            model: page.store.updates
            delegate: AppRow { required property var modelData; store: page.store; entry: modelData }
        }
        Text { visible: page.fromMarket.length > 0; text: qsTr("From Market"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.Bold; color: Theme.text; topPadding: 12 }
        Repeater {
            model: page.fromMarket
            delegate: AppRow {
                required property var modelData
                store: page.store
                entry: page.store.catalog.find(e => e.package === modelData.package)
                       || ({ package: modelData.package, name: modelData.name, summary: modelData.version, icon: modelData.iconUrl })
            }
        }
    }
}
