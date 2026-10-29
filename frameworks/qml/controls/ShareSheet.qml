// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Animation

// Share or open files with other apps. Apps list the types they accept in
// their app.json ("share": ["image/*"], "opens": ["text/plain"]) and receive
// them as launch arguments: { action: "share" | "open", files: [paths], text }.
//
//   ShareSheet { id: share }
//   share.open([path], "image/png")            // share
//   share.open([path], "text/plain", "open")    // open with
Item {
    id: root

    property var files: []
    property string text
    property string mimeType: "*/*"
    property string kind: "share"
    readonly property var targets: Packages.count >= 0 ? Packages.targets(mimeType, kind) : []
    signal done()

    anchors.fill: parent
    visible: reveal.value > 0.005
    z: 1000
    Spring { id: reveal; to: 0; response: 0.4; dampingFraction: 0.82 }

    function open(paths, mime, how, text) {
        files = paths || []
        mimeType = mime || "*/*"
        kind = how || "share"
        root.text = text || ""
        reveal.animateTo(1, 0)
    }
    function close() { reveal.animateTo(0, 0) }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.4 * Math.min(1, reveal.value)
        MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    Rectangle {
        x: 10
        width: parent.width - 20
        height: column.implicitHeight + 40
        y: parent.height - 12 - height + (1 - reveal.value) * (height + 40)
        radius: Theme.sheetRadius
        color: Theme.sheet
        MouseArea { anchors.fill: parent }

        Column {
            id: column
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 16
            Text {
                text: root.kind === "open" ? qsTr("Open with") : root.files.length > 1 ? qsTr("Share %n items", "", root.files.length) : qsTr("Share")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize + 1
                font.weight: Font.DemiBold
                color: Theme.text
            }
            Text {
                visible: root.targets.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("No app on this phone can take this kind of file.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.textSecondary
            }
            Flow {
                width: parent.width
                spacing: 14
                Repeater {
                    model: root.targets
                    delegate: Item {
                        id: target
                        required property var modelData
                        width: (column.width - 3 * 14) / 4
                        height: targetColumn.implicitHeight
                        Column {
                            id: targetColumn
                            width: parent.width
                            spacing: 6
                            AppIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 56; source: target.modelData.iconUrl }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: target.modelData.name
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.footnoteSize + 1
                                color: Theme.text
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Packages.launch(target.modelData.package, { action: root.kind, files: root.files, text: root.text })
                                root.close()
                                root.done()
                            }
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 48
                radius: 24
                color: Theme.surfaceRaised
                Text { anchors.centerIn: parent; text: qsTr("Cancel"); font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize
                       font.weight: Font.DemiBold; color: Theme.text }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }
        }
    }
}
