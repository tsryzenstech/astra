// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick
import Astra.Core

// Minute resolution wall clock shared by the whole shell.
QtObject {
    id: clock

    property date now: new Date()
    // Settings > Date & Time > 24-hour time
    readonly property bool use24h: Settings.values["clock.24h"] !== false
    readonly property string time: use24h ? Qt.locale().toString(now, "HH:mm") : Qt.locale().toString(now, "h:mm")
    // Dates follow the UI language (Language.current makes them re-evaluate).
    // "Sun, 22 September" (lock screen) and "Fri, 4 Oct 2024" (Notification Center)
    readonly property string longDate: { Language.current; return Qt.locale().toString(now, "ddd, d MMMM") }
    readonly property string shortDate: { Language.current; return Qt.locale().toString(now, "ddd, d MMM yyyy") }

    property Timer ticker: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const d = new Date()
            if (d.getMinutes() !== clock.now.getMinutes() || d.getHours() !== clock.now.getHours()
                    || d.getDate() !== clock.now.getDate())
                clock.now = d
        }
    }
}
