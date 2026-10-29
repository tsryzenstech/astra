// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Cloudy: the assistant of AI Space (Claude by Anthropic).
Page {
    id: page
    title: qsTr("Cloudy")
    readonly property var aiSpace: Packages.count >= 0 ? Packages.get("com.astra.aispace") : ({})

    EmptyState {
        iconName: "sparkles"
        title: qsTr("Cloudy")
        message: qsTr("Ask questions, plan your day, set timers and alarms, add events and open apps. Cloudy runs on Claude by Anthropic with your own API key.")
    }
    ListGroup {
        footer: qsTr("Your chats are sent to Anthropic to be answered and are kept only on this phone. The API key stays in AI Space's private storage.")
        SwitchRow {
            text: qsTr("Search the web from Cloudy")
            subtitle: qsTr("Cloudy can open web searches in Planet.")
            key: "cloudy.web"
            fallback: true
        }
        SwitchRow {
            text: qsTr("Control the phone")
            subtitle: qsTr("Timers, alarms, calendar events and apps.")
            key: "cloudy.actions"
            fallback: true
            separator: false
        }
    }
    ListGroup {
        ListItem {
            text: qsTr("Open AI Space")
            iconSource: page.aiSpace.iconUrl || ""
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.aispace")
        }
    }
}
