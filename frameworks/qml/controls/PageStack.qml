// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtQuick.Controls.Basic as Basic
import Astra.Animation

// Navigation stack with iOS style spring transitions and an edge swipe to go back.
Basic.StackView {
    id: root

    function open(component, properties) {
        const props = Object.assign({ stack: root }, properties || {})
        return root.push(component, props)
    }

    readonly property var spring: Motion.curve(0.42, 1.0)
    readonly property int springDuration: Motion.duration(0.42, 1.0)

    pushEnter: Transition {
        NumberAnimation { property: "x"; from: root.width; to: 0; duration: root.springDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.spring }
    }
    pushExit: Transition {
        NumberAnimation { property: "x"; from: 0; to: -root.width * 0.3; duration: root.springDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.spring }
        NumberAnimation { property: "opacity"; from: 1; to: 0.6; duration: root.springDuration }
    }
    popEnter: Transition {
        NumberAnimation { property: "x"; from: -root.width * 0.3; to: 0; duration: root.springDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.spring }
        NumberAnimation { property: "opacity"; from: 0.6; to: 1; duration: root.springDuration }
    }
    popExit: Transition {
        NumberAnimation { property: "x"; from: 0; to: root.width; duration: root.springDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: root.spring }
    }

    // Swipe from the left edge to go back.
    MouseArea {
        z: 100
        width: 18
        height: parent.height
        enabled: root.depth > 1
        property real startX: 0
        onPressed: (m) => startX = m.x
        onReleased: (m) => { if (m.x - startX > 60) root.pop() }
    }
}
