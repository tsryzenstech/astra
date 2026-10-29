// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QNetworkAccessManager>
#include <QUrl>

#include <QHash>
#include <QJsonArray>

#include <functional>

namespace astrad {

class DialogService;

// Installs, tracks and removes .apkg packages, and owns their permissions.
//
//  /system/priv-app/<Name>/<package>.apkg   privileged system apps
//  /system/app/<Name>/<package>.apkg        system apps
//  /product/app/<Name>/<package>.apkg       device/product apps
//  /data/app/<package>/base.apkg            user installed apps
//
// Every package is extracted to /data/app/<package>/code and gets its own
// uid (>= 10000) and private data directory /data/data/<package>.
// System apps are "installed by root" and cannot be uninstalled.
class PackageManager : public Service
{
    Q_OBJECT
public:
    PackageManager(Server *server, QObject *parent = nullptr);

    void scan();
    void setDialogs(DialogService *dialogs) { m_dialogs = dialogs; }
    // Current system language, used to localize app names.
    void setLanguageProvider(std::function<QString()> language) { m_language = std::move(language); }
    // Developer Options > Sideload Apps: when off, apps come only from Market.
    void setSideloadProvider(std::function<bool()> allowed) { m_sideload = std::move(allowed); }

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    bool contains(const QString &package) const { return m_packages.contains(package); }
    QStringList packages() const { return m_packages.keys(); }
    QJsonObject info(const QString &package) const;
    QString packageForUid(uid_t uid) const;
    QStringList permissionsOf(const QString &package) const;
    QList<gid_t> groupsOf(const QString &package) const;
    uid_t uidOf(const QString &package) const;
    QJsonArray widgets() const;
    bool isGranted(const QString &package, const QString &permission) const;
    QString displayName(const QString &package) const;

    // Asks the user (through a system dialog) for a runtime permission.
    // result(granted, restartRequired)
    void requestPermission(const QString &package, const QString &permission,
                           std::function<void(bool, bool)> result);

Q_SIGNALS:
    void packageRemoved(const QString &package);
    void permissionsChanged(const QString &package, bool groupsChanged);
    void dataCleared(const QString &package);

private:
    // Downloads an .apkg (Market) and installs it; result(error) on the main thread.
    void installUrl(const QUrl &url, const QString &sha256, const QString &installer, std::function<void(QString)> result);
    QNetworkAccessManager *m_network = nullptr;
    bool installFrom(const QString &apkgPath, bool system, bool privileged, const QString &installer, QString *error);
    void uninstall(const QString &package);
    uid_t allocateUid() const;
    void prepareDataDir(const QString &package, uid_t uid);
    void setRuntimeState(const QString &package, const QString &permission, const QString &state);
    QJsonArray permissionList(const QString &package) const;
    void save();

    Server *m_server;
    DialogService *m_dialogs = nullptr;
    std::function<QString()> m_language;
    std::function<bool()> m_sideload;
    QString m_dbPath;
    QHash<QString, QJsonObject> m_packages; // package -> record
};

} // namespace astrad
