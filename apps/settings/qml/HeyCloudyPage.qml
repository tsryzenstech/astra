// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > Cloudy: the on-device assistant.
Page {
    id: page
    title: qsTr("Cloudy")
    readonly property var aiSpace: Packages.count >= 0 ? Packages.get("com.astra.aispace") : ({})

    EmptyState {
        iconName: "sparkles"
        title: qsTr("Cloudy")
        message: qsTr("Ask questions, plan your day, set timers and alarms, add events and open apps. Cloudy runs on your phone: what you write stays here.")
    }
    ListGroup {
        footer: qsTr("Cloudy uses a small model downloaded once from Hugging Face (Qwen 2.5, Apache 2.0) and runs it with llama.cpp.")
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
            text: qsTr("Open Cloudy")
            iconSource: page.aiSpace.iconUrl || ""
            chevron: true
            separator: false
            onClicked: Packages.launch("com.astra.aispace")
        }
    }
}
