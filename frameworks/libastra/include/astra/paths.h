// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "global.h"

#include <QString>

namespace astra {

// Filesystem layout (see docs/FILESYSTEM.md).
//
// On a device every path is absolute. During development the whole tree can
// be relocated with the ASTRA_ROOT environment variable (e.g. out/root), so
// SysBoard, astrad and apps run unmodified on a desktop Linux machine.
class ASTRA_EXPORT Paths
{
public:
    static QString root();
    static QString resolve(const QString &absolutePath);
    static bool isDevelopmentRoot();

    static QString systemDir() { return resolve(QStringLiteral("/system")); }
    static QString systemApps() { return resolve(QStringLiteral("/system/app")); }
    static QString privilegedApps() { return resolve(QStringLiteral("/system/priv-app")); }
    static QString productApps() { return resolve(QStringLiteral("/product/app")); }
    static QString frameworkQml() { return resolve(QStringLiteral("/system/framework/qml")); }
    static QString fonts() { return resolve(QStringLiteral("/system/fonts")); }
    static QString media() { return resolve(QStringLiteral("/system/media")); }

    static QString dataDir() { return resolve(QStringLiteral("/data")); }
    static QString dataSystem() { return resolve(QStringLiteral("/data/system")); }
    static QString dataApp() { return resolve(QStringLiteral("/data/app")); }
    static QString dataData() { return resolve(QStringLiteral("/data/data")); }
    static QString userMedia() { return resolve(QStringLiteral("/data/media/0")); }

    static QString runtimeDir() { return resolve(QStringLiteral("/run/astra")); }
    static QString displayDir() { return resolve(QStringLiteral("/run/astra/display")); }
    static QString astradSocket() { return resolve(QStringLiteral("/dev/socket/astrad")); }
    static QString initSocket() { return resolve(QStringLiteral("/dev/socket/init")); }
    static QString bootAnimationControl() { return resolve(QStringLiteral("/run/astra/bootanim.ctl")); }
};

} // namespace astra
