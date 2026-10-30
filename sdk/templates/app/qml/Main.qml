import QtQuick
import Astra.Core
import Astra.Controls

// {{name}}: built only from Astra.Controls, so it looks and behaves like
// the rest of astraOS (light and dark mode, the user's text size, springs).
Page {
    id: page
    title: qsTr("{{name}}")
    actions: IconButton { iconName: "plus"; onClicked: sheet.open() }

    property int taps: 0

    Card {
        accented: true
        Column {
            width: parent.width
            spacing: 10
            Text {
                text: qsTr("Hello!")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Bold
                color: "white"
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("Edit qml/Main.qml in Astra Studio: the preview updates as you type.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: "white"
            }
        }
    }

    ListGroup {
        title: qsTr("Example")
        footer: qsTr("Tapped %n time(s)", "", page.taps)
        ListItem {
            text: qsTr("Tap me")
            iconName: "star"
            chevron: true
            onClicked: page.taps++
        }
        ListItem {
            text: qsTr("Post a notification")
            iconName: "notification"
            separator: false
            onClicked: Notifications.post(qsTr("{{name}}"), qsTr("Sent from my first astraOS app"))
        }
    }

    Sheet {
        id: sheet
        title: qsTr("New")
        Column {
            width: parent.width
            spacing: 14
            TextField { id: field; width: parent.width; placeholder: qsTr("Write something") }
            Button { width: parent.width; text: qsTr("Done"); onClicked: sheet.close() }
        }
    }
}
