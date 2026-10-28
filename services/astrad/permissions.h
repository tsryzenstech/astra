// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QList>
#include <QString>
#include <QStringList>

#include <sys/types.h>

// Permissions an app can request in app.json ("permissions": [...]).
//
//   normal      granted at install time (low risk)
//   runtime     the user decides, through a prompt the first time the app
//               asks (and later in Settings > Apps / Privacy)
//   privileged  only for apps in /system/priv-app
//
// Some permissions also give the app process a supplementary group (camera
// device nodes, shared media storage...). Groups are applied when the
// process starts, so granting one of them restarts the app.
namespace astrad::permissions {

constexpr const char INTERNET[] = "astra.permission.INTERNET";
constexpr const char VIBRATE[] = "astra.permission.VIBRATE";
constexpr const char ALARMS[] = "astra.permission.ALARMS";

constexpr const char NOTIFICATIONS[] = "astra.permission.NOTIFICATIONS";
constexpr const char CAMERA[] = "astra.permission.CAMERA";
constexpr const char MICROPHONE[] = "astra.permission.MICROPHONE";
constexpr const char LOCATION[] = "astra.permission.LOCATION";
constexpr const char CONTACTS[] = "astra.permission.CONTACTS";
constexpr const char CALENDAR[] = "astra.permission.CALENDAR";
constexpr const char MEDIA[] = "astra.permission.MEDIA";
constexpr const char PHONE[] = "astra.permission.PHONE";
constexpr const char SMS[] = "astra.permission.SMS";
constexpr const char NEARBY_DEVICES[] = "astra.permission.NEARBY_DEVICES";

constexpr const char MANAGE_SETTINGS[] = "astra.permission.MANAGE_SETTINGS";
constexpr const char MANAGE_LOCK[] = "astra.permission.MANAGE_LOCK";
constexpr const char MANAGE_PACKAGES[] = "astra.permission.MANAGE_PACKAGES";
constexpr const char MANAGE_NOTIFICATIONS[] = "astra.permission.MANAGE_NOTIFICATIONS";
constexpr const char MANAGE_NETWORK[] = "astra.permission.MANAGE_NETWORK";
constexpr const char MANAGE_THEMES[] = "astra.permission.MANAGE_THEMES";
constexpr const char MEDIA_CONTROL[] = "astra.permission.MEDIA_CONTROL";
constexpr const char HARDWARE[] = "astra.permission.HARDWARE";
constexpr const char POWER[] = "astra.permission.POWER";
constexpr const char DEVELOPER[] = "astra.permission.DEVELOPER";

enum class Level { Normal, Runtime, Privileged };

struct Info {
    const char *name;
    Level level;
    gid_t gid;           // supplementary group granted with the permission (0: none)
    const char *label;   // shown in prompts and Settings (English, translated by the UI)
    const char *icon;    // system icon name
};

inline const QList<Info> &all()
{
    static const QList<Info> table{
        {INTERNET, Level::Normal, 3003, "Full network access", "wifi"},
        {VIBRATE, Level::Normal, 0, "Vibration", "sound"},
        {ALARMS, Level::Normal, 0, "Alarms and timers", "clock"},
        {NOTIFICATIONS, Level::Runtime, 0, "Notifications", "notification"},
        {CAMERA, Level::Runtime, 1006, "Camera", "camera"},
        {MICROPHONE, Level::Runtime, 1005, "Microphone", "mic"},
        {LOCATION, Level::Runtime, 0, "Location", "location"},
        {CONTACTS, Level::Runtime, 0, "Contacts", "person"},
        {CALENDAR, Level::Runtime, 0, "Calendar", "calendar"},
        {MEDIA, Level::Runtime, 1023, "Photos, videos and music", "image"},
        {PHONE, Level::Runtime, 1001, "Phone calls", "phone"},
        {SMS, Level::Runtime, 1001, "SMS messages", "message"},
        {NEARBY_DEVICES, Level::Runtime, 1002, "Nearby devices", "bluetooth"},
        {MANAGE_SETTINGS, Level::Privileged, 0, "Change system settings", "settings"},
        {MANAGE_LOCK, Level::Privileged, 0, "Manage the screen lock", "lock"},
        {MANAGE_PACKAGES, Level::Privileged, 0, "Install and remove apps", "grid"},
        {MANAGE_NOTIFICATIONS, Level::Privileged, 0, "Manage all notifications", "notification"},
        {MANAGE_NETWORK, Level::Privileged, 0, "Manage networks", "wifi"},
        {MANAGE_THEMES, Level::Privileged, 0, "Change the system theme", "palette"},
        {MEDIA_CONTROL, Level::Privileged, 0, "Control media playback", "play"},
        {HARDWARE, Level::Privileged, 0, "Control hardware", "flashlight"},
        {POWER, Level::Privileged, 0, "Reboot the device", "power"},
        {DEVELOPER, Level::Privileged, 0, "Developer options", "code"},
    };
    return table;
}

inline const Info *find(const QString &name)
{
    for (const Info &i : all())
        if (name == QLatin1String(i.name))
            return &i;
    return nullptr;
}

inline bool isNormal(const QString &permission)
{
    const Info *i = find(permission);
    return i && i->level == Level::Normal;
}

inline bool isRuntime(const QString &permission)
{
    const Info *i = find(permission);
    return i && i->level == Level::Runtime;
}

} // namespace astrad::permissions
