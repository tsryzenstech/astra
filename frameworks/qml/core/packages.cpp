// SPDX-License-Identifier: Apache-2.0
#include "packages.h"
#include "common.h"

#include <astra/client.h>

#include <QJsonArray>

namespace astra::qml {

PackageModel::PackageModel(QObject *parent)
    : QAbstractListModel(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("packages")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        const QJsonObject o = data.toObject();
        const QString pkg = o.value(QLatin1String("package")).toString();
        if (name == QLatin1String("packages.changed")) {
            for (int i = 0; i < m_items.size(); ++i) {
                if (m_items.at(i).value(QLatin1String("package")).toString() == pkg) {
                    m_items[i] = o;
                    Q_EMIT dataChanged(index(i), index(i));
                    Q_EMIT packageChanged(pkg);
                    return;
                }
            }
            beginInsertRows({}, int(m_items.size()), int(m_items.size()));
            m_items.append(o);
            endInsertRows();
            Q_EMIT countChanged();
            Q_EMIT packageChanged(pkg);
        } else if (name == QLatin1String("packages.removed")) {
            for (int i = 0; i < m_items.size(); ++i) {
                if (m_items.at(i).value(QLatin1String("package")).toString() == pkg) {
                    beginRemoveRows({}, i, i);
                    m_items.removeAt(i);
                    endRemoveRows();
                    Q_EMIT countChanged();
                    Q_EMIT packageChanged(pkg);
                    return;
                }
            }
        }
    });
    if (c->isConnected())
        reload();
}

void PackageModel::reload()
{
    Client::instance()->call(QStringLiteral("packages.list"), {}, [this](const QJsonValue &r, const QString &) {
        beginResetModel();
        m_items.clear();
        for (const QJsonValue &v : r.toArray())
            m_items.append(v.toObject());
        std::sort(m_items.begin(), m_items.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value(QLatin1String("name")).toString().compare(b.value(QLatin1String("name")).toString(), Qt::CaseInsensitive) < 0;
        });
        endResetModel();
        Q_EMIT countChanged();
        if (!m_ready) {
            m_ready = true;
            Q_EMIT readyChanged();
        }
    });
}

QVariantMap PackageModel::toMap(const QJsonObject &o)
{
    QVariantMap m = o.toVariantMap();
    m.insert(QStringLiteral("iconUrl"), fileUrl(o.value(QLatin1String("icon")).toString()));
    return m;
}

int PackageModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant PackageModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const QJsonObject &p = m_items.at(index.row());
    switch (role) {
    case PackageRole: return p.value(QLatin1String("package")).toString();
    case NameRole: return p.value(QLatin1String("name")).toString();
    case IconRole: return fileUrl(p.value(QLatin1String("icon")).toString());
    case VersionRole: return p.value(QLatin1String("version")).toString();
    case SystemRole: return p.value(QLatin1String("system")).toBool();
    case RemovableRole: return p.value(QLatin1String("removable")).toBool();
    case BackgroundRole: return p.value(QLatin1String("background")).toString();
    case LauncherRole: return p.value(QLatin1String("launcher")).toBool();
    case WidgetsRole: return p.value(QLatin1String("widgets")).toArray().toVariantList();
    }
    return {};
}

QHash<int, QByteArray> PackageModel::roleNames() const
{
    return {
        {PackageRole, "packageName"}, {NameRole, "name"},           {IconRole, "icon"},
        {VersionRole, "version"},     {SystemRole, "system"},       {RemovableRole, "removable"},
        {BackgroundRole, "background"}, {LauncherRole, "launcher"}, {WidgetsRole, "widgets"},
    };
}

QVariantList PackageModel::widgets() const
{
    QVariantList out;
    for (const QJsonObject &p : m_items)
        for (const QJsonValue &w : p.value(QLatin1String("widgets")).toArray()) {
            QVariantMap m = w.toObject().toVariantMap();
            m.insert(QStringLiteral("appName"), p.value(QLatin1String("name")).toString());
            m.insert(QStringLiteral("iconUrl"), fileUrl(p.value(QLatin1String("icon")).toString()));
            m.insert(QStringLiteral("qmlUrl"), fileUrl(w.toObject().value(QLatin1String("qml")).toString()));
            out.append(m);
        }
    return out;
}

QVariantMap PackageModel::get(const QString &package) const
{
    for (const QJsonObject &p : m_items)
        if (p.value(QLatin1String("package")).toString() == package)
            return toMap(p);
    return {};
}

QVariantList PackageModel::list() const
{
    QVariantList out;
    for (const QJsonObject &p : m_items)
        out.append(toMap(p));
    return out;
}

QVariantMap PackageModel::widget(const QString &key) const
{
    for (const QVariant &w : widgets())
        if (w.toMap().value(QStringLiteral("key")).toString() == key)
            return w.toMap();
    return {};
}

void PackageModel::launch(const QString &package, const QVariantMap &args, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("activity.start"),
                             {{QStringLiteral("package"), package}, {QStringLiteral("args"), QJsonObject::fromVariantMap(args)}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

void PackageModel::uninstall(const QString &package, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.uninstall"), {{QStringLiteral("package"), package}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r, e); });
}

QVariantList PackageModel::targets(const QString &mimeType, const QString &kind) const
{
    QVariantList out;
    const QString self = qEnvironmentVariable("ASTRA_PACKAGE");
    for (const QJsonObject &p : m_items) {
        if (p.value(QLatin1String("package")).toString() == self)
            continue;
        for (const QJsonValue &v : p.value(kind == QLatin1String("open") ? QLatin1String("opens") : QLatin1String("share")).toArray()) {
            const QString pattern = v.toString();
            const bool match = pattern == QLatin1String("*/*") || pattern == mimeType ||
                               (pattern.endsWith(QLatin1String("/*")) && mimeType.startsWith(pattern.chopped(1)));
            if (match) {
                out.append(toMap(p));
                break;
            }
        }
    }
    return out;
}

void PackageModel::details(const QString &package, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("packages.get"), {{QStringLiteral("package"), package}},
                             [this, callback](const QJsonValue &r, const QString &e) {
                                 invokeCallback(this, callback, r.isObject() ? QJsonValue(QJsonObject::fromVariantMap(toMap(r.toObject()))) : r, e);
                             });
}

} // namespace astra::qml
