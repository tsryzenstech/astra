// SPDX-License-Identifier: Apache-2.0
#include "contactsservice.h"
#include "jsonstore.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QRegularExpression>

namespace astrad {

using namespace astra;

namespace {
QString digits(const QString &number)
{
    static const QRegularExpression nonDigits(QStringLiteral("[^0-9+]"));
    QString d = number;
    d.remove(nonDigits);
    return d.right(9); // compare national numbers regardless of prefix
}
} // namespace

ContactsService::ContactsService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_path(Paths::dataSystem() + QStringLiteral("/contacts.json"))
{
    const QJsonObject stored = loadJson(m_path);
    m_contacts = stored.value(QLatin1String("contacts")).toArray();
    m_nextId = qMax(1, stored.value(QLatin1String("nextId")).toInt());
}

void ContactsService::save()
{
    saveJson(m_path, {{QStringLiteral("contacts"), m_contacts}, {QStringLiteral("nextId"), m_nextId}});
    m_server->broadcast(QStringLiteral("contacts.changed"), QJsonValue(),
                        [](const Caller &c) { return c.can(QLatin1String(permissions::CONTACTS)); });
    if (m_changed)
        m_changed();
}

int ContactsService::merge(const QJsonArray &contacts)
{
    int added = 0;
    for (const QJsonValue &v : contacts) {
        QJsonObject c = sanitize(v.toObject());
        const QString name = c.value(QLatin1String("name")).toString();
        const QString phone = digits(c.value(QLatin1String("phone")).toString());
        if (name.isEmpty() && phone.isEmpty())
            continue;
        bool known = false;
        for (const QJsonValue &e : std::as_const(m_contacts)) {
            const QJsonObject o = e.toObject();
            if (o.value(QLatin1String("name")).toString() == name && digits(o.value(QLatin1String("phone")).toString()) == phone)
                known = true;
        }
        if (known)
            continue;
        c.insert(QStringLiteral("id"), m_nextId++);
        m_contacts.append(c);
        ++added;
    }
    if (added)
        save();
    return added;
}

QJsonObject ContactsService::sanitize(const QJsonObject &in)
{
    QJsonObject out;
    for (const char *key : {"name", "phone", "email", "note", "company"})
        if (in.contains(QLatin1String(key)))
            out.insert(QLatin1String(key), in.value(QLatin1String(key)).toString().left(200).trimmed());
    if (in.contains(QLatin1String("favorite")))
        out.insert(QStringLiteral("favorite"), in.value(QLatin1String("favorite")).toBool());
    return out;
}

QString ContactsService::nameForNumber(const QString &number) const
{
    const QString d = digits(number);
    for (const QJsonValue &v : m_contacts)
        if (!d.isEmpty() && digits(v.toObject().value(QLatin1String("phone")).toString()) == d)
            return v.toObject().value(QLatin1String("name")).toString();
    return {};
}

QJsonValue ContactsService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::CONTACTS));
    const int id = params.value(QLatin1String("id")).toInt();

    if (call == QLatin1String("list"))
        return m_contacts;
    if (call == QLatin1String("lookup"))
        return nameForNumber(params.value(QLatin1String("number")).toString());
    if (call == QLatin1String("add")) {
        QJsonObject c = sanitize(params);
        if (c.value(QLatin1String("name")).toString().isEmpty() && c.value(QLatin1String("phone")).toString().isEmpty())
            throw RpcError{protocol::InvalidParams, QStringLiteral("a contact needs a name or a number")};
        c.insert(QStringLiteral("id"), m_nextId++);
        m_contacts.append(c);
        save();
        return c;
    }
    if (call == QLatin1String("update")) {
        for (int i = 0; i < m_contacts.size(); ++i) {
            QJsonObject c = m_contacts.at(i).toObject();
            if (c.value(QLatin1String("id")).toInt() != id)
                continue;
            const QJsonObject changes = sanitize(params);
            for (auto it = changes.begin(); it != changes.end(); ++it)
                c.insert(it.key(), it.value());
            m_contacts.replace(i, c);
            save();
            return c;
        }
        throw RpcError{protocol::NotFound, QStringLiteral("no contact %1").arg(id)};
    }
    if (call == QLatin1String("delete")) {
        for (int i = 0; i < m_contacts.size(); ++i)
            if (m_contacts.at(i).toObject().value(QLatin1String("id")).toInt() == id) {
                m_contacts.removeAt(i);
                save();
                return true;
            }
        return false;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
