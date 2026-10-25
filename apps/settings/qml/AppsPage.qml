// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

Page {
    title: "Apps"

    ListGroup {
        Repeater {
            model: Packages
            delegate: ListItem {
                required property int index
                required property string packageName
                required property string name
                required property url icon
                required property string version
                required property bool system
                text: name
                subtitle: packageName + "  •  " + version + (system ? "  •  system" : "")
                iconSource: icon
                chevron: true
                separator: index < Packages.count - 1
                onClicked: stack.open(Qt.resolvedUrl("AppInfoPage.qml"), { packageName: packageName })
            }
        }
    }
}
