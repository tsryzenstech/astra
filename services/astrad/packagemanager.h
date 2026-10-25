// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QHash>
#include <QJsonArray>

namespace astrad {

// Installs, tracks and removes .apkg packages.
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

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    bool contains(const QString &package) const { return m_packages.contains(package); }
    QJsonObject info(const QString &package) const;
    QString packageForUid(uid_t uid) const;
    QStringList permissionsOf(const QString &package) const;
    uid_t uidOf(const QString &package) const;
    QJsonArray widgets() const;

Q_SIGNALS:
    void packageRemoved(const QString &package);

private:
    bool installFrom(const QString &apkgPath, bool system, bool privileged, const QString &installer, QString *error);
    void uninstall(const QString &package);
    uid_t allocateUid() const;
    void prepareDataDir(const QString &package, uid_t uid);
    void save();

    Server *m_server;
    QString m_dbPath;
    QHash<QString, QJsonObject> m_packages; // package -> record
};

} // namespace astrad
