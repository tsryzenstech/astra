// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QAbstractListModel>
#include <QJSValue>
#include <QJsonObject>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// Installed packages (QML singleton "Packages").
class PackageModel : public QAbstractListModel
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Packages)
    QML_SINGLETON

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QVariantList widgets READ widgets NOTIFY countChanged)

public:
    enum Roles {
        PackageRole = Qt::UserRole + 1,
        NameRole,
        IconRole,
        VersionRole,
        SystemRole,
        RemovableRole,
        BackgroundRole,
        LauncherRole,
        WidgetsRole,
    };

    explicit PackageModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_items.size()); }
    bool ready() const { return m_ready; }
    QVariantList widgets() const;

    Q_INVOKABLE QVariantMap get(const QString &package) const;
    Q_INVOKABLE QVariantList list() const;
    Q_INVOKABLE QVariantMap widget(const QString &key) const;
    Q_INVOKABLE void launch(const QString &package, const QVariantMap &args = QVariantMap(),
                            const QJSValue &callback = QJSValue());
    Q_INVOKABLE void uninstall(const QString &package, const QJSValue &callback = QJSValue());
    Q_INVOKABLE void details(const QString &package, const QJSValue &callback);
    // Apps that declared they open ("open") or receive ("share") a MIME type.
    Q_INVOKABLE QVariantList targets(const QString &mimeType, const QString &kind = QStringLiteral("share")) const;

Q_SIGNALS:
    void countChanged();
    void readyChanged();
    void packageChanged(const QString &package);

private:
    void reload();
    static QVariantMap toMap(const QJsonObject &o);

    QList<QJsonObject> m_items;
    bool m_ready = false;
};

} // namespace astra::qml
