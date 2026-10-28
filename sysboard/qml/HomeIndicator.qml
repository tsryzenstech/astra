// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// The bar at the bottom of every screen. While an app is swiped away it
// rides along under the shrinking window; when the finger lets go it snaps
// back to its place like a magnet (a bouncy, slightly overshooting spring).
Item {
    id: root

    property bool following: false
    property real followX: 0   // finger offset from where the gesture began
    property real followY: 0   // upwards, positive

    width: parent.width
    height: 30

    Spring { id: ox; to: 0; response: 0.42; dampingFraction: 0.55 }
    Spring { id: oy; to: 0; response: 0.42; dampingFraction: 0.55 }
    Spring { id: stretch; to: 0; response: 0.3; dampingFraction: 0.6 }

    onFollowXChanged: if (following) ox.value = followX * 0.6
    onFollowYChanged: if (following) {
        oy.value = -followY
        stretch.value = Math.min(1, followY / 160)
    }
    onFollowingChanged: {
        if (!following) {
            ox.animateTo(0, 0)
            oy.animateTo(0, 0)
            stretch.animateTo(0, 0)
        }
    }

    // Lets go with the finger's velocity for a livelier snap.
    function release(vx, vy) {
        following = false
        ox.animateTo(0, -vx / 400)
        oy.animateTo(0, vy / 400)
    }

    Rectangle {
        x: (root.width - width) / 2 + ox.value
        y: root.height - 9 - height + oy.value
        width: 120 + 26 * stretch.value
        height: 5
        radius: 2.5
        color: "white"
    }
}
