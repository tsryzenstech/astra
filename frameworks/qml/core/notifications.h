// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QAbstractListModel>
#include <QJSValue>
#include <QJsonObject>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// Live list of notifications (QML singleton "Notifications").
// SysBoard sees everything; apps see and post their own.
class NotificationModel : public QAbstractListModel
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Notifications)
    QML_SINGLETON

    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        PackageRole,
        AppNameRole,
        IconRole,
        TitleRole,
        BodyRole,
        TimeRole,
        OngoingRole,
        ProgressRole,
        ArgsRole,
    };

    explicit NotificationModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_items.size()); }

    Q_INVOKABLE void post(const QString &title, const QString &body, const QString &package = QString(),
                          const QJSValue &callback = QJSValue());
    // Full form: { title, body, ongoing, progress (0..1, -1 = unknown), args }.
    // An ongoing notification can't be dismissed by the user and ends when
    // the app updates it with ongoing: false, dismisses it or exits.
    //   Notifications.notify({ title: "Downloading", ongoing: true, progress: 0 }, (id) => ...)
    Q_INVOKABLE void notify(const QVariantMap &options, const QJSValue &callback = QJSValue());
    // Changes a posted notification: { title, body, ongoing, progress, args, alert }
    // (alert: true shows the banner again).
    Q_INVOKABLE void update(int id, const QVariantMap &changes);
    Q_INVOKABLE void dismiss(int id);
    // { notificationId, packageName, appName, icon, title, body, time } or {} if gone
    Q_INVOKABLE QVariantMap get(int id) const;
    Q_INVOKABLE void clear();

Q_SIGNALS:
    void countChanged();
    void posted(int id);
    void updated(int id);

private:
    void reload();
    void removeId(int id);

    QList<QJsonObject> m_items;
};

} // namespace astra::qml
