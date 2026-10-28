// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Hey Cloudy: the voice assistant of AI Space.
Page {
    id: page
    title: qsTr("Hey Cloudy")

    readonly property var aiSpace: Packages.count >= 0 ? Packages.get("com.astra.aispace") : ({})

    EmptyState {
        iconName: "sparkles"
        title: qsTr("Hey Cloudy")
        message: qsTr("Ask questions, set timers and control your phone with your voice. Cloudy lives in AI Space.")
    }

    ListGroup {
        SwitchRow {
            text: qsTr("Listen for “Hey Cloudy”")
            subtitle: qsTr("Needs the microphone permission of AI Space.")
            key: "cloudy.wake_word"
        }
        SwitchRow { text: qsTr("Allow on the lock screen"); key: "cloudy.lockscreen"; separator: false }
    }

    ListGroup {
        ListItem {
            text: qsTr("Voice language")
            value: Language.nameOf(Settings.values["cloudy.language"] || Language.current)
            chevron: true
            onClicked: stack.open(Qt.resolvedUrl("ChoicePage.qml"), {
                title: qsTr("Voice language"), key: "cloudy.language",
                options: Language.available.map(l => ({ value: l.code, label: l.name })) })
        }
        ListItem {
            text: qsTr("Open AI Space")
            iconSource: page.aiSpace.iconUrl || ""
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.aispace")
        }
    }
}
