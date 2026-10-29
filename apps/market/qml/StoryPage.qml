// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// A Today story, opened: the picture, the text and its apps.
Page {
    id: page
    property var store
    property var story
    title: ""

    Rectangle {
        width: parent.width
        height: 260
        radius: Theme.cardRadius
        clip: true
        color: page.story.color
        Image { anchors.fill: parent; visible: page.story.image !== ""; source: page.story.image; fillMode: Image.PreserveAspectCrop }
        AppIcon {
            visible: page.story.image === "" && page.story.apps.length > 0
            anchors.centerIn: parent
            size: 120
            source: page.story.apps.length ? page.story.apps[0].icon : ""
        }
    }
    Text { text: (page.story.eyebrow || "").toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.Bold; color: Theme.textSecondary }
    Text { width: parent.width; wrapMode: Text.WordWrap; text: page.story.title; font.family: Theme.fontFamily; font.pixelSize: Theme.largeTitleSize; font.weight: Font.Bold; color: Theme.text }
    Text { visible: !!page.story.subtitle; width: parent.width; wrapMode: Text.WordWrap; text: page.story.subtitle; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; color: Theme.textSecondary }
    Text {
        visible: !!page.story.body
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.MarkdownText
        text: page.story.body
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize + 1
        lineHeight: 1.3
        color: Theme.text
    }
    Repeater {
        model: page.story.apps
        delegate: AppRow { required property var modelData; store: page.store; entry: modelData }
    }
}
