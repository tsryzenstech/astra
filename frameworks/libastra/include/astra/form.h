// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "global.h"

#include <QString>

namespace astra {

// The form factor astraOS runs on (docs/DESKTOP.md).
//
//   phone    the touch OS: one app full screen, home screen, Recents.
//   desktop  astraOS Desktop: windows, menu bar and Dock.
//
// Read from ro.astra.form (build.prop) and, in a development tree, from the
// ASTRA_FORM environment variable (ASTRA_FORM=desktop scripts/dev-run.sh).
class ASTRA_EXPORT Form
{
public:
    static QString current();                // "phone" or "desktop"
    static bool isDesktop();
    static bool isPhone() { return !isDesktop(); }

    // The "target" of a package (app.json): "mobile" (default) or "desktop".
    // Mobile apps run on both form factors, desktop apps only on the desktop.
    static QString normalizeTarget(const QString &target);
    static bool runsHere(const QString &target);

    // A mobile app on the desktop lives in a window with a phone's aspect
    // ratio that can not be resized: logical size of that window.
    static constexpr int phoneWindowWidth = 393;
    static constexpr int phoneWindowHeight = 852;
};

} // namespace astra
