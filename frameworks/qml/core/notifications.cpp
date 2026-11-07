// SPDX-License-Identifier: Apache-2.0
#include "notifications.h"
#include "common.h"

#include <astra/client.h>

#include <QDateTime>
#include <QJsonArray>

namespace astra::qml {

NotificationModel::NotificationModel(QObject *parent)
    : QAbstractListModel(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("notifications")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("notifications.posted")) {
            const QJsonObject n = data.toObject();
            removeId(n.value(QLatin1String("id")).toInt()); // never duplicate after a reconnect
            beginInsertRows({}, 0, 0);
            m_items.prepend(n);
            endInsertRows();
            Q_EMIT countChanged();
            Q_EMIT posted(n.value(QLatin1String("id")).toInt());
        } else if (name == QLatin1String("notifications.updated")) {
            const QJsonObject n = data.toObject();
            const int id = n.value(QLatin1String("id")).toInt();
            for (int i = 0; i < m_items.size(); ++i) {
                if (m_items.at(i).value(QLatin1String("id")).toInt() != id)
                    continue;
                if (n.value(QLatin1String("alert")).toBool() && i > 0) {
                    // Back to the top, like a new notification.
                    beginMoveRows({}, i, i, {}, 0);
                    m_items.move(i, 0);
                    endMoveRows();
                    i = 0;
                }
                m_items[i] = n;
                Q_EMIT dataChanged(index(i), index(i));
                break;
            }
            Q_EMIT updated(id);
            if (n.value(QLatin1String("alert")).toBool())
                Q_EMIT posted(id);
        } else if (name == QLatin1String("notifications.removed")) {
            removeId(data.toObject().value(QLatin1String("id")).toInt());
        } else if (name == QLatin1String("notifications.cleared")) {
            beginResetModel();
            m_items.clear();
            endResetModel();
            Q_EMIT countChanged();
        }
    });
    if (c->isConnected())
        reload();
}

void NotificationModel::reload()
{
    Client::instance()->call(QStringLiteral("notifications.list"), {}, [this](const QJsonValue &r, const QString &) {
        beginResetModel();
        m_items.clear();
        for (const QJsonValue &v : r.toArray())
            m_items.append(v.toObject());
        endResetModel();
        Q_EMIT countChanged();
    });
}

void NotificationModel::removeId(int id)
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).value(QLatin1String("id")).toInt() == id) {
            beginRemoveRows({}, i, i);
            m_items.removeAt(i);
            endRemoveRows();
            Q_EMIT countChanged();
            return;
        }
    }
}

int NotificationModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant NotificationModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const QJsonObject &n = m_items.at(index.row());
    switch (role) {
    case IdRole: return n.value(QLatin1String("id")).toInt();
    case PackageRole: return n.value(QLatin1String("package")).toString();
    case AppNameRole: return n.value(QLatin1String("appName")).toString();
    case IconRole: return fileUrl(n.value(QLatin1String("icon")).toString());
    case TitleRole: return n.value(QLatin1String("title")).toString();
    case BodyRole: return n.value(QLatin1String("body")).toString();
    case TimeRole: return QDateTime::fromMSecsSinceEpoch(qint64(n.value(QLatin1String("time")).toDouble()));
    case OngoingRole: return n.value(QLatin1String("ongoing")).toBool();
    case ProgressRole: return n.contains(QLatin1String("progress")) ? n.value(QLatin1String("progress")).toDouble() : -2.0; // -2: no bar
    case ArgsRole: return n.value(QLatin1String("args")).toObject().toVariantMap();
    }
    return {};
}

QVariantMap NotificationModel::get(int id) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).value(QLatin1String("id")).toInt() != id)
            continue;
        QVariantMap out;
        const QHash<int, QByteArray> roles = roleNames();
        for (auto it = roles.cbegin(); it != roles.cend(); ++it)
            out.insert(QString::fromLatin1(it.value()), data(index(i), it.key()));
        return out;
    }
    return {};
}

QHash<int, QByteArray> NotificationModel::roleNames() const
{
    return {
        {IdRole, "notificationId"}, {PackageRole, "packageName"}, {AppNameRole, "appName"}, {IconRole, "icon"},
        {TitleRole, "title"},       {BodyRole, "body"},           {TimeRole, "time"},
        {OngoingRole, "ongoing"},   {ProgressRole, "progress"}, {ArgsRole, "args"},
    };
}

void NotificationModel::post(const QString &title, const QString &body, const QString &package, const QJSValue &callback)
{
    QJsonObject params{{QStringLiteral("title"), title}, {QStringLiteral("body"), body}};
    if (!package.isEmpty())
        params.insert(QStringLiteral("package"), package);
    Client::instance()->call(QStringLiteral("notifications.post"), params,
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void NotificationModel::notify(const QVariantMap &options, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("notifications.post"), QJsonObject::fromVariantMap(options),
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void NotificationModel::update(int id, const QVariantMap &changes)
{
    QJsonObject params = QJsonObject::fromVariantMap(changes);
    params.insert(QStringLiteral("id"), id);
    Client::instance()->call(QStringLiteral("notifications.update"), params);
}

void NotificationModel::dismiss(int id)
{
    Client::instance()->call(QStringLiteral("notifications.dismiss"), {{QStringLiteral("id"), id}});
}

void NotificationModel::clear()
{
    Client::instance()->call(QStringLiteral("notifications.clear"));
}

} // namespace astra::qml
