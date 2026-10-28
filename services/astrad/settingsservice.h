// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

namespace astrad {

// System wide key/value settings.
//
// Defaults ship in /system/etc/settings/defaults.json, user changes are
// stored in /data/system/settings.json. Everyone can read (except keys under
// "secure."), only the system and MANAGE_SETTINGS holders can write.
class SettingsService : public Service
{
    Q_OBJECT
public:
    SettingsService(Server *server, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    QJsonValue value(const QString &key) const;
    void setValue(const QString &key, const QJsonValue &value);

Q_SIGNALS:
    void changed(const QString &key, const QJsonValue &value);

private:
    bool mayWrite(const QString &key, const Caller &caller) const;

    Server *m_server;
    QString m_path;
    QJsonObject m_defaults;
    QJsonObject m_values;
};

} // namespace astrad
