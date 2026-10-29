// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Animation

// Wraps one Control/Notification Center component and makes it drop in from
// the top with a bouncy spring, staggered by order.
Item {
    id: root

    property var panel
    property int order: 0
    default property alias content: holder.data

    readonly property real dragProgress: Math.pow(Math.max(0, Math.min(1.1, panel.reveal)), 1 + order * 0.2)
    readonly property real progress: panel.dragging ? dragProgress : spring.value

    Spring { id: spring; to: 0; response: 0.52; dampingFraction: 0.62 }

    Connections {
        target: root.panel
        function onOpenedChanged() {
            spring.value = root.dragProgress
            stagger.interval = root.panel.opened ? root.order * Motion.stagger : 0
            stagger.restart()
        }
    }
    // A notification that arrives while the panel is open drops in at once.
    Component.onCompleted: if (panel && panel.opened) spring.animateTo(1, 0)
    Timer {
        id: stagger
        onTriggered: spring.animateTo(root.panel.opened ? 1 : 0, 0)
    }

    Item {
        id: holder
        anchors.fill: parent
        opacity: Math.max(0, Math.min(1, root.progress * 1.4))
        scale: 0.86 + 0.14 * Math.min(1.05, root.progress)
        transform: Translate { y: -(1 - root.progress) * (90 + root.order * 14) }
    }
}
