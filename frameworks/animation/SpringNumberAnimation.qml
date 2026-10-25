// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// A NumberAnimation that follows a spring curve, usable in Behaviors and
// Transitions:  Behavior on x { SpringNumberAnimation { preset: Motion.bouncy } }
NumberAnimation {
    property var preset: Motion.smooth
    property real response: preset.response
    property real dampingFraction: preset.dampingFraction

    duration: Motion.duration(response, dampingFraction)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.curve(response, dampingFraction)
}
