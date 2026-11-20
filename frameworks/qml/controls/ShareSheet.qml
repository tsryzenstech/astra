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
//
// Sharing (not "open with") also lists the devices nearby, to send them the files with PetalDrop, the
// system's own way of sending to a phone or computer near you (astrad's petaldrop service: no app).
Item {
    id: root

    property var files: []
    property string text
    property string mimeType: "*/*"
    property string kind: "share"
    readonly property var targets: Packages.count >= 0 ? Packages.targets(mimeType, kind) : []
    signal done()

    // PetalDrop: the devices nearby, looked up while the sheet is open.
    property var peers: []
    property string petalStatus: ""
    property int petalTransfer: 0
    readonly property bool petalAvailable: kind === "share" && files.length > 0 && !text
    function refreshPeers() {
        PetalDrop.call("peers", {}, function(result, error) {
            root.peers = error || !result ? [] : result
        })
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.visible && root.petalAvailable
        onTriggered: root.refreshPeers()
    }
    function sendTo(peer) {
        petalStatus = qsTr("Sending to %1...").arg(peer.name)
        PetalDrop.call("send", { peer: peer.id, files: root.files }, function(result, error) {
            if (error) {
                root.petalStatus = qsTr("PetalDrop: %1").arg(error)
            } else {
                root.petalTransfer = result.id
                root.petalStatus = qsTr("Sending to %1...").arg(peer.name)
            }
        })
    }
    Connections {
        target: PetalDrop
        function onEvent(name, data) {
            if (name !== "transfer" || data.id !== root.petalTransfer)
                return
            if (data.state === "done")
                root.petalStatus = qsTr("Sent to %1").arg(data.peer)
            else if (data.state === "declined")
                root.petalStatus = qsTr("%1 declined").arg(data.peer)
            else if (data.state === "failed")
                root.petalStatus = data.error || qsTr("Could not send")
        }
    }

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
            // PetalDrop
            Column {
                visible: root.petalAvailable
                width: parent.width
                spacing: 8
                Text {
                    text: qsTr("PetalDrop")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
                Text {
                    visible: root.peers.length === 0 && root.petalStatus === ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: qsTr("Looking for devices nearby. They must be on the same network, with PetalDrop on.")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize + 1
                    color: Theme.textTertiary
                }
                Flow {
                    width: parent.width
                    spacing: 14
                    Repeater {
                        model: root.peers
                        delegate: Item {
                            id: peer
                            required property var modelData
                            width: (column.width - 3 * 14) / 4
                            height: peerColumn.implicitHeight
                            Column {
                                id: peerColumn
                                width: parent.width
                                spacing: 6
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 56; height: 56; radius: 28
                                    color: peer.modelData.mine ? Theme.accent : Theme.surfaceRaised
                                    Icon { anchors.centerIn: parent; name: peer.modelData.kind === "desktop" ? "desktop" : "phone"; size: 26
                                           color: peer.modelData.mine ? Theme.accentText : Theme.text }
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: peer.modelData.name
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.footnoteSize + 1
                                    color: Theme.text
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.sendTo(peer.modelData) }
                        }
                    }
                }
                Text {
                    visible: root.petalStatus !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: root.petalStatus
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.footnoteSize + 1
                    color: Theme.text
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
