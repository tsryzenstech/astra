// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// The widgets on the left of the desktop. They are the apps' home screen widgets (app.json "widgets"
// with "home"), the same ones the phone's home screen shows; which ones is "desktop.widgets"
// (default: Weather and Calendar).
Column {
    id: root

    property var shell
    readonly property real tile: 168
    readonly property var wanted: Settings.values["desktop.widgets"]
        || ["com.astra.weather/home", "com.astra.calendar/home"]
    readonly property var keys: Packages.count >= 0 ? wanted.filter(k => Packages.widget(k).key) : []

    spacing: 18
    Repeater {
        model: root.keys
        delegate: HomeWidget {
            required property string modelData
            widgetKey: modelData
            size: "small"
            shell: root.shell
            width: root.tile
            height: root.tile
        }
    }
}
