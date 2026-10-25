// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QString>
#include <QStringList>

// Permissions an app can request in app.json ("permissions": [...]).
// Privileged apps (/system/priv-app) are granted everything they request,
// other apps only the "normal" ones.
namespace astrad::permissions {

constexpr const char INTERNET[] = "astra.permission.INTERNET";
constexpr const char MANAGE_SETTINGS[] = "astra.permission.MANAGE_SETTINGS";
constexpr const char MANAGE_LOCK[] = "astra.permission.MANAGE_LOCK";
constexpr const char MANAGE_PACKAGES[] = "astra.permission.MANAGE_PACKAGES";
constexpr const char MANAGE_NOTIFICATIONS[] = "astra.permission.MANAGE_NOTIFICATIONS";
constexpr const char MEDIA_CONTROL[] = "astra.permission.MEDIA_CONTROL";
constexpr const char HARDWARE[] = "astra.permission.HARDWARE";
constexpr const char POWER[] = "astra.permission.POWER";

inline bool isNormal(const QString &permission)
{
    return permission == QLatin1String(INTERNET);
}

} // namespace astrad::permissions
