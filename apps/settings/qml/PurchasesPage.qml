// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Store Purchases: apps that came from Market.
Page {
    id: page
    title: qsTr("Store Purchases")

    readonly property var fromMarket: (Packages.count >= 0 ? Packages.list() : []).filter(p => p.installer === "com.astra.market")

    EmptyState {
        visible: page.fromMarket.length === 0
        iconName: "bag"
        title: qsTr("No purchases yet")
        message: qsTr("Apps you get from Market appear here, ready to install again on your other devices.")
    }

    ListGroup {
        visible: page.fromMarket.length > 0
        Repeater {
            model: page.fromMarket
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                subtitle: modelData.version
                iconSource: modelData.iconUrl
                chevron: true
                separator: index < page.fromMarket.length - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: modelData.package })
            }
        }
    }

    ListGroup {
        ListItem {
            text: qsTr("Open Market")
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.market")
        }
    }
}
