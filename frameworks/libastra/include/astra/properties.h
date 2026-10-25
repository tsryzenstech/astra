// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "global.h"

#include <QHash>
#include <QString>

namespace astra {

// Read-only build properties (Android style key=value files):
//   /system/build.prop, /vendor/build.prop, /product/build.prop
// Later files override earlier ones, so a device can tune system defaults.
class ASTRA_EXPORT Properties
{
public:
    static QString get(const QString &key, const QString &fallback = QString());
    static int getInt(const QString &key, int fallback);
    static double getReal(const QString &key, double fallback);
    static bool getBool(const QString &key, bool fallback);
    static QHash<QString, QString> all();

    static QHash<QString, QString> parse(const QByteArray &contents);
};

} // namespace astra
