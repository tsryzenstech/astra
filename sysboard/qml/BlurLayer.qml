// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Effects

// Live blurred + dimmed copy of another item. Used behind Control Center,
// Notification Center, the PIN pad, app context menus and search.
Item {
    id: root

    property Item source
    property real amount: 0      // 0..1 blur strength
    property real dim: 0.3       // darkening at full amount
    property bool hideSource: false

    visible: amount > 0.001

    ShaderEffectSource {
        id: snapshot
        anchors.fill: parent
        sourceItem: root.visible ? root.source : null
        hideSource: root.hideSource && root.amount > 0.98
        live: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: snapshot
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: Math.min(1, root.amount)
        saturation: 0.15 * root.amount
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.dim * Math.min(1, root.amount)
    }
}
