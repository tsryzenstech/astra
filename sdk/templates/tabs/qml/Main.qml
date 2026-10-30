import QtQuick
import Astra.Core
import Astra.Controls

// {{name}}: three sections behind a TabBar, each with its own pages.
Item {
    id: app

    readonly property var sections: [
        { icon: "home", label: qsTr("Home") },
        { icon: "search", label: qsTr("Search") },
        { icon: "settings", label: qsTr("Settings") }
    ]

    Repeater {
        model: [homePage, searchPage, settingsPage]
        delegate: PageStack {
            required property var modelData
            required property int index
            anchors.fill: parent
            anchors.bottomMargin: tabs.height
            visible: index === tabs.currentIndex
            Component.onCompleted: open(modelData)
        }
    }

    TabBar {
        id: tabs
        model: app.sections
        tint: Application.accent.valid ? Application.accent : Theme.accent
    }

    Component {
        id: homePage
        Page {
            title: qsTr("Home")
            EmptyState {
                iconName: "home"
                title: qsTr("{{name}}")
                message: qsTr("Each tab keeps its own pages. Tap a tab again to go back to its top.")
            }
        }
    }
    Component {
        id: searchPage
        Page {
            title: qsTr("Search")
            TextField { width: parent.width; placeholder: qsTr("Search") }
        }
    }
    Component {
        id: settingsPage
        Page {
            title: qsTr("Settings")
            ListGroup {
                // App settings live under "app.<package>." in the system store.
                ListItem {
                    text: qsTr("Notifications")
                    iconName: "notification"
                    showSwitch: true
                    checked: Settings.values["app.{{package}}.notifications"] !== false
                    separator: false
                    onToggled: (on) => Settings.setValue("app.{{package}}.notifications", on)
                }
            }
        }
    }
}
