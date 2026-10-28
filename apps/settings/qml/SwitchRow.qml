// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// A switch bound to a boolean system setting.
ListItem {
    property string key
    property bool fallback: false

    showSwitch: true
    checked: Settings.values[key] === undefined ? fallback : !!Settings.values[key]
    onToggled: (on) => Settings.setValue(key, on)
}
