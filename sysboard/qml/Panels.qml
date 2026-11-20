// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Notification Center (left) and Control Center (right).
//
// They are not sheets sliding down: the screen blurs in place (except the
// status bar) and every component drops in from the top with a bouncy,
// staggered spring. Swiping sideways moves between the two; past the outer
// edges the content follows the finger with resistance and snaps back like
// a magnet. Tap an empty area or swipe up to close.
Item {
    id: panels

    property var shell
    property Item blurSource
    // The two centers are as wide as the screen on the phone. On the desktop they are a column of
    // their own (astraOS Desktop sets the width and the position of the column).
    property real contentWidth: width
    property real contentLeft: 0
    // astraOS Desktop: the Notification Center (it opens from the clock) is a column in the middle of the screen and
    // the Control Center a column on the right, each in its own place and with nothing blurred under them.
    readonly property bool columns: contentWidth < width
    property real notificationsLeft: (width - contentWidth) / 2
    readonly property real columnLift: 84

    readonly property real reveal: revealSpring.value
    readonly property real page: pageSpring.value        // 0 = notifications, 1 = controls
    property bool dragging: false
    property bool opened: false
    readonly property bool interacting: dragging || closer.active

    visible: reveal > 0.001 || dragging
    Spring { id: revealSpring; to: 0; response: 0.42; dampingFraction: 0.86 }
    Spring { id: pageSpring; to: 0; response: 0.36; dampingFraction: 0.84 }

    function beginDrag(kind) {
        pageSpring.snap(kind === "controls" ? 1 : 0)
        dragging = true
        opened = false
    }
    function drag(dy) {
        const p = dy / 280
        revealSpring.value = p <= 1 ? Math.max(0, p) : 1 + Motion.rubberband(p - 1, 1, 0.4)
    }
    function endDrag(vy) {
        const open = revealSpring.value > 0.3 || vy > 450
        opened = open           // entrance items snapshot their drag progress first
        dragging = false
        revealSpring.animateTo(open ? 1 : 0, vy / 280)
    }
    function open(kind) {
        if (panels.columns && Host.installer)
            return      // the recovery environment has no centers
        pageSpring.snap(kind === "controls" ? 1 : 0)
        opened = true
        revealSpring.animateTo(1, 0)
    }
    function close() {
        if (!opened && !dragging && revealSpring.value < 0.001)
            return
        opened = false
        dragging = false
        revealSpring.animateTo(0, 0)
    }

    BlurLayer {
        visible: !panels.columns
        anchors.fill: parent
        source: panels.blurSource
        amount: Math.min(1, panels.reveal)
        dim: 0.38
        hideSource: true
    }

    // Empty-area gestures: tap or swipe up closes, swipe sideways switches.
    MouseArea {
        id: closer
        anchors.fill: parent
        enabled: panels.opened
        preventStealing: true
        property point start
        property real startPage: 0
        property string mode: ""
        property bool active: pressed && mode !== ""
        VelocityTracker { id: velocity }

        onPressed: (m) => {
            start = Qt.point(m.x, m.y)
            startPage = Math.round(pageSpring.value)
            mode = ""
            velocity.reset()
            velocity.addPoint(m.x, m.y)
        }
        onPositionChanged: (m) => {
            velocity.addPoint(m.x, m.y)
            const dx = m.x - start.x, dy = m.y - start.y
            if (mode === "" && Math.hypot(dx, dy) > 10)
                mode = Math.abs(dx) > Math.abs(dy) ? "page" : (dy < 0 ? "close" : "")
            if (mode === "page") {
                let p = startPage - dx / width
                if (p < 0)
                    p = -Motion.rubberband(-p, 1, 0.45)
                else if (p > 1)
                    p = 1 + Motion.rubberband(p - 1, 1, 0.45)
                pageSpring.value = p
            } else if (mode === "close") {
                revealSpring.value = Math.max(0, 1 + dy / 420)
            }
        }
        onReleased: (m) => {
            const v = velocity.velocity()
            if (mode === "page") {
                let target = startPage
                if (pageSpring.value - startPage > 0.25 || v.x < -500)
                    target = 1
                else if (startPage - pageSpring.value > 0.25 || v.x > 500)
                    target = 0
                pageSpring.animateTo(target, -v.x / width)
            } else if (mode === "close") {
                if (revealSpring.value < 0.8 || v.y < -500)
                    panels.close()
                else
                    revealSpring.animateTo(1, -v.y / 420)
            } else {
                panels.close() // tap on an empty area
            }
            mode = ""
        }
    }

    Item {
        x: panels.columns ? 0 : panels.contentLeft
        // On the desktop the columns start higher (they are cards near the bar, not a full phone screen).
        y: panels.columns ? -panels.columnLift : 0
        width: panels.columns ? panels.width : panels.contentWidth
        height: panels.height
        clip: !panels.columns && panels.contentWidth < panels.width

        NotificationCenter {
            x: panels.columns ? panels.notificationsLeft : -panels.page * panels.contentWidth
            width: panels.contentWidth
            height: panels.height
            visible: !panels.columns || panels.page < 0.5
            panel: panels
            shell: panels.shell
        }

        ControlCenter {
            x: panels.columns ? panels.contentLeft : (1 - panels.page) * panels.contentWidth
            width: panels.contentWidth
            height: panels.height
            visible: !panels.columns || panels.page >= 0.5
            panel: panels
            shell: panels.shell
        }
    }
}
