// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects
import QtMultimedia
import Astra.Core
import Astra.Controls
import Astra.Animation

// Full screen viewer. Opens by growing out of the tapped thumbnail and
// closes back into it. Swipe sideways between items, pinch or double tap
// to zoom, swipe down to close (the photo follows the finger and the
// background fades). Tap to hide or show the bars.
Item {
    id: root

    property var list: []
    property int index: 0
    property Item origin: null
    property bool chrome: true
    property var isFavorite: function(p) { return false }
    readonly property var current: list.length ? list[Math.max(0, Math.min(index, list.length - 1))] : null
    readonly property bool active: openSpring.to > 0.5
    property rect from: Qt.rect(0, 0, 0, 0)
    property bool showInfo: false

    signal toggleFavorite(string path)
    signal deleted()

    visible: openSpring.value > 0.005
    Spring { id: openSpring; to: 0; response: 0.45; dampingFraction: 0.84 }
    // Swipe-down to dismiss
    Spring { id: dragY; to: 0; response: 0.35; dampingFraction: 0.8 }
    Spring { id: dragX; to: 0; response: 0.35; dampingFraction: 0.8 }
    readonly property real dismiss: Math.min(1, Math.max(0, dragY.value) / (height * 0.4))

    function open(items, i, fromItem) {
        list = items
        index = i
        origin = fromItem
        from = fromItem ? fromItem.mapToItem(root, 0, 0, fromItem.width, fromItem.height) : Qt.rect(width / 2, height / 2, 0, 0)
        chrome = true
        showInfo = false
        dragX.snap(0)
        dragY.snap(0)
        pages.positionViewAtIndex(i, ListView.Beginning)
        pages.currentIndex = i
        openSpring.snap(0)
        openSpring.animateTo(1, 0)
    }
    function close() {
        // Back into the thumbnail of the current item when it is the one we came from.
        openSpring.animateTo(0, 0)
        player.stop()
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Math.min(1, openSpring.value) * (1 - root.dismiss * 0.9)
    }

    // While opening/closing: the photo flies between the thumbnail and full screen.
    Item {
        id: flight
        readonly property real t: Math.max(0, Math.min(1.05, openSpring.value))
        visible: openSpring.running || openSpring.value < 0.999
        x: root.from.x + (0 - root.from.x) * t
        y: root.from.y + (0 - root.from.y) * t
        width: Math.max(1, root.from.width + (root.width - root.from.width) * t)
        height: Math.max(1, root.from.height + (root.height - root.from.height) * t)
        Image {
            id: flightImage
            anchors.fill: parent
            source: root.current && !root.current.video ? root.current.url : ""
            sourceSize.width: 1080
            fillMode: flight.t > 0.5 ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle { id: flightMask; anchors.fill: parent; radius: 14 * (1 - flight.t); visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: flightImage
            maskEnabled: true
            maskSource: flightMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
    }

    ListView {
        id: pages
        anchors.fill: parent
        visible: !flight.visible
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 250
        boundsBehavior: Flickable.StopAtBounds
        interactive: !currentItemZoomed
        spacing: 20
        model: root.list
        readonly property bool currentItemZoomed: currentItem ? currentItem.zoomed : false
        onCurrentIndexChanged: {
            root.index = currentIndex
            player.stop()
        }

        delegate: Item {
            id: page
            required property var modelData
            required property int index
            width: pages.width
            height: pages.height
            readonly property bool zoomed: zoom.contentWidth > zoom.width + 1
            transform: Translate {
                x: page.index === pages.currentIndex ? dragX.value : 0
                y: page.index === pages.currentIndex ? Math.max(0, dragY.value) : 0
            }
            scale: page.index === pages.currentIndex ? 1 - root.dismiss * 0.35 : 1

            Flickable {
                id: zoom
                anchors.fill: parent
                visible: !page.modelData.video
                contentWidth: width
                contentHeight: height
                boundsBehavior: Flickable.StopAtBounds
                interactive: page.zoomed
                clip: true

                PinchArea {
                    width: Math.max(zoom.contentWidth, zoom.width)
                    height: Math.max(zoom.contentHeight, zoom.height)
                    property real initialWidth
                    property real initialHeight
                    onPinchStarted: {
                        initialWidth = zoom.contentWidth
                        initialHeight = zoom.contentHeight
                    }
                    onPinchUpdated: (pinch) => {
                        zoom.contentX += pinch.previousCenter.x - pinch.center.x
                        zoom.contentY += pinch.previousCenter.y - pinch.center.y
                        zoom.resizeContent(Math.max(zoom.width, Math.min(zoom.width * 5, initialWidth * pinch.scale)),
                                           Math.max(zoom.height, Math.min(zoom.height * 5, initialHeight * pinch.scale)), pinch.center)
                    }
                    onPinchFinished: zoom.returnToBounds()

                    Image {
                        width: zoom.contentWidth
                        height: zoom.contentHeight
                        source: page.modelData.video ? "" : page.modelData.url
                        sourceSize.width: 2160
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        onDoubleClicked: (m) => {
                            if (page.zoomed)
                                zoom.resizeContent(zoom.width, zoom.height, Qt.point(m.x, m.y))
                            else
                                zoom.resizeContent(zoom.width * 2.5, zoom.height * 2.5, Qt.point(m.x, m.y))
                            zoom.returnToBounds()
                        }
                        onClicked: root.chrome = !root.chrome
                    }
                }
            }

            // Video
            Item {
                anchors.fill: parent
                visible: page.modelData.video
                VideoOutput {
                    id: video
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }
                IconButton {
                    anchors.centerIn: parent
                    visible: player.playbackState !== MediaPlayer.PlayingState || page.index !== pages.currentIndex
                    size: 72
                    iconName: "play"
                    color: Qt.rgba(0, 0, 0, 0.45)
                    onClicked: {
                        player.videoOutput = video
                        player.source = page.modelData.url
                        player.play()
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: {
                        if (player.playbackState === MediaPlayer.PlayingState)
                            player.pause()
                        else
                            root.chrome = !root.chrome
                    }
                }
            }
        }

        // Swipe down to close (only when not zoomed).
        MouseArea {
            anchors.fill: parent
            enabled: !pages.currentItemZoomed
            propagateComposedEvents: true
            property point start
            property bool dragging: false
            onPressed: (m) => {
                start = Qt.point(m.x, m.y)
                dragging = false
                m.accepted = true
            }
            onPositionChanged: (m) => {
                const dx = m.x - start.x, dy = m.y - start.y
                if (!dragging && dy > 14 && dy > Math.abs(dx) * 1.2) {
                    dragging = true
                    preventStealing = true
                }
                if (dragging) {
                    dragY.value = dy
                    dragX.value = dx * 0.7
                }
            }
            onReleased: (m) => {
                if (dragging) {
                    if (root.dismiss > 0.25) {
                        root.from = root.origin && pages.currentIndex === root.list.indexOf(root.current) && root.origin.visible
                                    ? root.origin.mapToItem(root, 0, 0, root.origin.width, root.origin.height)
                                    : Qt.rect(root.width / 2 - 40 + dragX.value, root.height / 2 + dragY.value, 80, 80)
                        dragX.snap(0)
                        dragY.snap(0)
                        root.close()
                    } else {
                        dragX.animateTo(0, 0)
                        dragY.animateTo(0, 0)
                    }
                } else {
                    m.accepted = false
                }
                dragging = false
                preventStealing = false
            }
            onClicked: (m) => m.accepted = false
            onDoubleClicked: (m) => m.accepted = false
        }
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
    }

    // ---- bars -----------------------------------------------------------------
    Rectangle {
        width: parent.width
        height: Theme.statusBarHeight + 56
        opacity: root.chrome && !flight.visible ? 1 - root.dismiss * 2 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.75) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
        }
        IconButton {
            x: 14
            y: Theme.statusBarHeight + 4
            size: 40
            iconName: "chevron-left"
            color: Qt.rgba(1, 1, 1, 0.14)
            onClicked: root.close()
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.statusBarHeight + 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.current ? Qt.locale().toString(root.current.modified, "d MMMM yyyy") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.current ? Qt.locale().toString(root.current.modified, "HH:mm") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize + 1
                color: Theme.textSecondary
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34
        width: 236
        height: 56
        radius: 28
        color: Qt.rgba(0.16, 0.16, 0.18, 0.92)
        opacity: root.chrome && !flight.visible ? 1 - root.dismiss * 2 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Row {
            anchors.centerIn: parent
            spacing: 18
            IconButton {
                size: 42
                color: "transparent"
                iconName: "heart"
                iconColor: root.current && root.isFavorite(root.current.path) ? "#FF375F" : "white"
                onClicked: if (root.current) root.toggleFavorite(root.current.path)
            }
            IconButton {
                size: 42
                color: root.showInfo ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                iconName: "info"
                onClicked: root.showInfo = !root.showInfo
            }
            IconButton {
                size: 42
                color: "transparent"
                iconName: "trash"
                iconColor: Theme.danger
                onClicked: {
                    const item = root.current
                    if (!item)
                        return
                    Dialogs.show({
                        title: item.video ? qsTr("Delete this video?") : qsTr("Delete this photo?"), icon: "trash",
                        message: qsTr("It is removed from this phone."),
                        buttons: [ { id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" } ]
                    }, function(b) {
                        if (b !== "delete" || !Application.removeMedia(item.path))
                            return
                        const rest = root.list.filter(i => i.path !== item.path)
                        if (rest.length === 0) {
                            root.from = Qt.rect(root.width / 2, root.height / 2, 0, 0)
                            root.close()
                        }
                        root.list = rest
                        root.index = Math.min(root.index, rest.length - 1)
                        root.deleted()
                    })
                }
            }
        }
    }

    // Info sheet
    Rectangle {
        readonly property var info: root.current && root.showInfo ? Application.imageInfo(root.current.path) : ({})
        visible: root.showInfo && root.chrome
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 104
        width: parent.width - 32
        height: infoCol.implicitHeight + 32
        radius: Theme.cardRadius
        color: Qt.rgba(0.16, 0.16, 0.18, 0.95)
        Column {
            id: infoCol
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 4
            Text {
                text: root.current ? root.current.name : ""
                width: parent.width
                elide: Text.ElideMiddle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: "white"
            }
            Text {
                text: root.current ? Qt.locale().toString(root.current.modified, "dddd d MMMM yyyy • HH:mm") : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
            Text {
                readonly property var i: parent.parent.info
                text: (i.width ? i.width + " × " + i.height + "  •  " : "") + (root.current ? (root.current.size / 1048576).toFixed(1) + " MB" : "")
                       + (root.current ? "  •  " + root.current.folder : "")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }
        }
    }
}
