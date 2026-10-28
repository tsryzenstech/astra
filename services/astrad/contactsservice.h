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

private:
    void save();
    static QJsonObject sanitize(const QJsonObject &in);

    Server *m_server;
    QString m_path;
    QJsonArray m_contacts;
    int m_nextId = 1;
};

} // namespace astrad
