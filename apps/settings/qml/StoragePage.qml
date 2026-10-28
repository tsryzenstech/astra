// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Storage: used and free space of /data and the biggest apps.
Page {
    id: page
    title: qsTr("Storage")

    readonly property var info: System.info
    readonly property double total: info.storageTotal || 0
    readonly property double free: info.storageFree || 0
    readonly property double used: Math.max(0, total - free)
    property var sizes: []

    function format(bytes) {
        if (bytes >= 1e9)
            return (bytes / 1e9).toFixed(1) + " GB"
        if (bytes >= 1e6)
            return (bytes / 1e6).toFixed(1) + " MB"
        return Math.max(1, Math.round(bytes / 1e3)) + " KB"
    }

    Component.onCompleted: {
        const apps = Packages.list()
        const out = []
        let pending = apps.length
        for (const a of apps) {
            Packages.details(a.package, function(d) {
                if (d)
                    out.push({ package: a.package, name: a.name, icon: a.iconUrl, bytes: d.sizeBytes || 0 })
                if (--pending === 0)
                    page.sizes = out.sort((x, y) => y.bytes - x.bytes)
            })
        }
    }

    Card {
        Column {
            width: parent.width
            spacing: 12
            Text {
                text: qsTr("%1 of %2 used").arg(page.format(page.used)).arg(page.format(page.total))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 2
                font.weight: Font.DemiBold
                color: Theme.text
            }
            ProgressBar {
                width: parent.width
                height: 12
                value: page.total > 0 ? page.used / page.total : 0
            }
            Text {
                text: qsTr("%1 free").arg(page.format(page.free))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize + 1
                color: Theme.textSecondary
            }
        }
    }

    ListGroup {
        title: qsTr("Apps")
        Repeater {
            model: page.sizes
            delegate: ListItem {
                required property var modelData
                required property int index
                text: modelData.name
                iconSource: modelData.icon
                value: page.format(modelData.bytes)
                chevron: true
                separator: index < page.sizes.length - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: modelData.package })
            }
        }
        ListItem {
            visible: page.sizes.length === 0
            text: qsTr("Calculating…")
            busy: true
            separator: false
        }
    }
}
