// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>
#include <QJsonArray>
#include <QSet>

class QFileSystemWatcher;
class QProcess;
class QTimer;

namespace astrad {

class NotificationService;
class PackageManager;
class SettingsService;

// MyDroid's Android environment: a modern Android (LineageOS, as Waydroid
// publishes it) in a container, its apps on the home screen.
//
// Waydroid (packaged by Alpine) does the container: "waydroid init" downloads
// the Android images to /data/var/lib/waydroid, init's waydroid-container
// service runs the container (root), and the session (the Android user space
// that draws on SysBoard, in one full screen window) runs on its own session bus. Each
// Android app gets a launcher entry ("android.<package>", PackageManager
// shortcut); SysBoard gives the Android window to the Android app opened last.
// Android's notifications are shown as the app's astraOS notifications, so its
// home badge counts them.
//
//   android.status                 {available, installed, running, busy, progress, step, error, variant, apps: [...]}
//   android.setup  {variant}       download and prepare Android ("vanilla", or "gapps" with Google's services)
//   android.start / android.stop / android.restart   the environment (it also
//                                  starts by itself with the phone when MyDroid
//                                  is installed and Android downloaded)
//   android.install {path}         an APK from the phone's storage
//   android.launch {package}       an Android app (what its home icon does)
//   android.remove {package}       uninstall an Android app
//   android.reset                  remove Android and its apps from the phone
//   events: android.changed (the status)
//
// Only MyDroid (com.astra.mydroid) and the system may use it.
class AndroidService : public Service
{
    Q_OBJECT
public:
    AndroidService(Server *server, PackageManager *packages, NotificationService *notifications,
                   SettingsService *settings, QObject *parent = nullptr);
    ~AndroidService() override;

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    // The home icon of an Android app was tapped (ActivityManager).
    void launchApp(const QString &androidPackage);
    // The Wayland display SysBoard registered (for the session).
    void setDisplay(const QString &socket) { m_display = socket; }

private:
    QJsonObject status() const;
    void changed();
    bool installed() const;
    void setup(const QString &variant);
    void start();
    void stop();
    void startSession();
    void reset();
    void installApk(const QString &path, std::function<void(QString)> done);
    void refreshApps();
    void listApps();
    void waitForApp(const QString &androidPackage);   // until Android lists it
    void syncShortcuts(const QJsonArray &apps);
    void pollNotifications();
    // Runs a waydroid command; as MyDroid's user when asUser (session commands).
    QProcess *waydroid(const QStringList &args, bool asUser, std::function<void(int, QString)> done);
    QString userHome() const;

    Server *m_server;
    PackageManager *m_packages;
    NotificationService *m_notifications;
    SettingsService *m_settings;
    QProcess *m_setup = nullptr;
    QProcess *m_session = nullptr;
    QProcess *m_bus = nullptr;      // the session bus of Waydroid's session and commands
    QTimer *m_poll;
    QFileSystemWatcher *m_launchers = nullptr;
    int m_ticks = 0;
    bool m_refreshing = false;
    QString m_display;
    QString m_step;          // what is happening ("download", "starting"...)
    QString m_error;
    double m_progress = -1;
    bool m_running = false;
    QJsonArray m_apps;       // [{package, name, shortcut}]
    QHash<QString, int> m_posted; // Android notification key -> astraOS notification id
    QHash<QString, int> m_waiting; // just installed -> times Android was asked
};

} // namespace astrad
