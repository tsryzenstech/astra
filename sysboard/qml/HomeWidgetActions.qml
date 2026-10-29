// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick
import Astra.Core

// What a tap on a home screen widget does: system widgets open their app,
// app widgets open the app that made them.
QtObject {
    function activate(key, shell) {
        if (key === "system/greeting")
            shell.launch("com.astra.weather", {}, null)
        else if (key === "system/search")
            shell.launch("com.astra.planet", { mode: "search" }, null)
        else {
            const w = Packages.widget(key) || {}
            if (w.package)
                shell.launch(w.package, { widget: w.id }, null)
        }
    }
}
