// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "backends.h"
#include "dbusutil.h"

#include <QSet>

namespace astrad::network {

class MMCellular : public CellularBackend
{
    Q_OBJECT
public:
    explicit MMCellular(QObject *parent);

    QString kind() const override { return QStringLiteral("modemmanager"); }
    bool available() const override { return !m_modem.isEmpty(); }
    QJsonObject state() const override;
    void setDataEnabled(bool on, Done done) override;
    void setApn(const QString &apn) override { m_apn = apn; }
    void setAllowRoaming(bool on) override { m_allowRoaming = on; }
    QJsonArray calls() const override;
    void dial(const QString &number, Done done) override;
    void accept(const QString &id) override;
    void hangup(const QString &id) override;
    void sendSms(const QString &number, const QString &text, Done done) override;

private Q_SLOTS:
    void onSmsAdded(const QDBusObjectPath &path, bool received);

private:
    void refresh();
    QVariantMap props(const QString &path, const QString &iface) const;
    void applyBearer(const QString &bearerPath);
    void enableModem();

    DBusWatcher *m_watcher;
    ManagedObjects m_objects;
    ManagedObjects m_calls;
    QString m_modem;
    QString m_bearer;
    QString m_apn = QStringLiteral("internet");
    bool m_allowRoaming = false;
    bool m_dataWanted = false;
    QSet<QString> m_connectedSignals;
};

} // namespace astrad::network
