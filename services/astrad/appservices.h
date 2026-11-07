// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>

class QProcess;
class QTimer;

namespace astrad {

class PackageManager;
class SettingsService;

// Background services of apps: native programs an app ships in its package and
// declares in app.json, which keep running without the app's window (a
// messaging app's connection, an environment the app manages):
//
//   "services": [{ "id": "sync", "exec": "bin/sync", "args": ["--quiet"] }]
//
// Each runs as the app's uid, with its groups and its data folder as home,
// from the start of the phone (and on install), and starts again a few seconds
// after it stops (later each time it keeps failing). An update or "clear data"
// restarts it, uninstalling stops it. Its output goes to cache/<id>.log in the
// app's data folder. Only astraOS's own apps (com.astra.*, which only astraOS
// publishes on Market) may have services.
//
//   services.list        [{package, id, pid, running, restarts}] (system, or the app's own)
//   services.restart     {package} the app's services (the app itself or the system)
class AppServices : public Service
{
    Q_OBJECT
public:
    AppServices(Server *server, PackageManager *packages, SettingsService *settings, QObject *parent = nullptr);
    ~AppServices() override;

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;
    // Starts the services of every installed app (once astrad is up).
    void startAll();

private:
    struct Instance {
        QString package;
        QString id;
        QProcess *process = nullptr;
        QTimer *retry = nullptr;
        int failures = 0;
        qint64 started = 0;
        bool stopping = false;
    };
    static QString key(const QString &package, const QString &id) { return package + QLatin1Char('/') + id; }
    void sync(const QString &package);          // starts / restarts what the package declares
    void stopPackage(const QString &package);
    void launch(const QString &k);
    void scheduleRetry(const QString &k);

    Server *m_server;
    PackageManager *m_packages;
    SettingsService *m_settings;
    QHash<QString, Instance> m_instances;
};

} // namespace astrad
