// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonArray>

namespace astrad {

// The address book shared by Phone, Messages, MeetUp and Contacts.
//   contacts.list, contacts.add {name, phone, email, favorite, note}
//   contacts.update {id, ...}, contacts.delete {id}          CONTACTS
class ContactsService : public Service
{
    Q_OBJECT
public:
    ContactsService(Server *server, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;
    QString nameForNumber(const QString &number) const;
    QJsonArray all() const { return m_contacts; }
    // Adds the contacts that are not on the phone yet (same name and number); returns how many.
    int merge(const QJsonArray &contacts);
    void setChangedHook(std::function<void()> hook) { m_changed = std::move(hook); }

private:
    void save();
    static QJsonObject sanitize(const QJsonObject &in);

    Server *m_server;
    QString m_path;
    QJsonArray m_contacts;
    int m_nextId = 1;
    std::function<void()> m_changed;
};

} // namespace astrad
