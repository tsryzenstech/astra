// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Today: the date, big story cards (App of the Day, Game of the Day and the
// editors' features), the top apps and what's new.
Flickable {
    id: page
    required property var store
    readonly property var t: store.today
    contentHeight: column.height + 40
    boundsBehavior: Flickable.DragOverBounds

    Column {
        id: column
        x: 20
        y: Theme.statusBarHeight + 16
        width: parent.width - 40
        spacing: 26

        Item {
            width: parent.width
            height: 64
            Column {
                Text {
                    text: Qt.locale().toString(new Date(), "dddd d MMMM").toUpperCase()
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: Theme.textSecondary
                }
                Text { text: qsTr("Today"); font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 38; height: 38; radius: 19
                gradient: Gradient { GradientStop { position: 0; color: "#7B2FF7" } GradientStop { position: 1; color: "#00C9A7" } }
                Text { anchors.centerIn: parent; text: (Settings.values["account.name"] || "A").charAt(0).toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 17; font.weight: Font.Bold; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: Packages.launch("com.astra.astraid") }
            }
        }

        Column {
            visible: page.store.error !== "" && !page.t
            width: parent.width
            spacing: 12
            EmptyState { width: parent.width; iconName: "cloud"; title: qsTr("Market"); message: page.store.error }
            Button { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Try Again"); onClicked: page.store.load() }
        }
        Spinner { visible: page.store.loading && !page.t; anchors.horizontalCenter: parent.horizontalCenter }

        StoryCard { visible: !!(page.t && page.t.appOfTheDay); story: page.t ? page.t.appOfTheDay : null; store: page.store; width: parent.width }
        Repeater {
            model: page.t ? page.t.stories.slice(0, 2) : []
            delegate: StoryCard { required property var modelData; story: modelData; store: page.store; width: column.width }
        }

        // Top apps
        Card {
            visible: !!page.t && page.t.top.length > 0
            width: parent.width
            padding: 18
            Column {
                width: parent.width
                Text { text: qsTr("TOP APPS"); font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Bold; color: Theme.textSecondary }
                Text { text: qsTr("Most downloaded this week"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text; bottomPadding: 8 }
                Repeater {
                    model: page.t ? page.t.top.slice(0, 4) : []
                    delegate: AppRow { required property var modelData; required property int index; store: page.store; entry: modelData; rank: index + 1 }
                }
            }
        }

        StoryCard { visible: !!(page.t && page.t.gameOfTheDay); story: page.t ? page.t.gameOfTheDay : null; store: page.store; width: parent.width }
        Repeater {
            model: page.t ? page.t.stories.slice(2) : []
            delegate: StoryCard { required property var modelData; story: modelData; store: page.store; width: column.width }
        }

        // New
        Column {
            visible: !!page.t && page.t.fresh.length > 0
            width: parent.width
            spacing: 8
            Text { text: qsTr("New on Market"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            ListView {
                width: parent.width
                height: 150
                orientation: ListView.Horizontal
                spacing: 14
                clip: true
                model: page.t ? page.t.fresh : []
                delegate: Column {
                    required property var modelData
                    width: 92
                    spacing: 6
                    AppIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 84; source: modelData.icon || "" }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.text }
                    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.category; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.textSecondary }
                    TapHandler { onTapped: page.store.openPage(parent.modelData) }
                }
            }
        }
    }

    // A big rounded card: colour or picture, eyebrow, title, the apps.
    component StoryCard: Rectangle {
        id: card
        property var story: null
        property var store
        readonly property var first: story && story.apps && story.apps.length ? story.apps[0] : null
        height: story && story.kind === "list" ? 150 + Math.min(4, story.apps.length) * 76 : 420
        radius: Theme.cardRadius
        clip: true
        color: story ? story.color : Theme.surface
        scale: tap.pressed ? 0.97 : 1
        Behavior on scale { SpringNumberAnimation { preset: Motion.bouncy } }

        Image {
            anchors.fill: parent
            visible: !!card.story && card.story.image !== ""
            source: card.story ? card.story.image : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        // Without a picture: the app icon, big, on the colour.
        AppIcon {
            visible: !!card.first && (!card.story.image) && card.story.kind !== "list"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -20
            size: 150
            source: card.first ? card.first.icon : ""
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                GradientStop { position: 0.4; color: "transparent" }
                GradientStop { position: 0.75; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
        Column {
            x: 20; y: 18
            width: parent.width - 40
            Text { text: card.story ? (card.story.eyebrow || "").toUpperCase() : ""; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold; color: Qt.rgba(1, 1, 1, 0.8) }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: card.story ? card.story.title : ""; font.family: Theme.fontFamily; font.pixelSize: 30; font.weight: Font.Bold; color: "white"; lineHeight: 0.95 }
        }
        Column {
            visible: !!card.story && card.story.kind === "list"
            x: 16; y: 120
            width: parent.width - 32
            Repeater {
                model: card.story && card.story.kind === "list" ? card.story.apps.slice(0, 4) : []
                delegate: AppRow { required property var modelData; store: card.store; entry: modelData }
            }
        }
        // Bottom: the app with its GET button, or the subtitle.
        Item {
            visible: !!card.story && card.story.kind !== "list"
            anchors.bottom: parent.bottom
            width: parent.width
            height: 82
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25) }
            Row {
                visible: !!card.first
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                AppIcon { anchors.verticalCenter: parent.verticalCenter; size: 48; source: card.first ? card.first.icon : "" }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: card.width - 48 - 12 - 32 - 100
                    Text { width: parent.width; elide: Text.ElideRight; text: card.first ? card.first.name : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: "white" }
                    Text { width: parent.width; elide: Text.ElideRight; text: card.story ? (card.story.subtitle || (card.first ? card.first.summary : "")) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Qt.rgba(1, 1, 1, 0.75) }
                }
            }
            Text {
                visible: !card.first
                x: 20
                width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                text: card.story ? card.story.subtitle : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize + 1
                color: "white"
            }
        }
        TapHandler { id: tap; onTapped: card.store.openStory(card.story) }
        GetButton {
            visible: !!card.first && card.story.kind !== "list"
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 26
            store: card.store
            entry: card.first || ({})
        }
    }
}
