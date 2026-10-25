// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// System settings (QML singleton "Settings").
//   Text { text: Settings.values["account.name"] }
//   Settings.setValue("lockscreen.clock_weight", "Bold")
class SettingsStore : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Settings)
    QML_SINGLETON

    Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY valuesChanged)

public:
    explicit SettingsStore(QObject *parent = nullptr);

    QVariantMap values() const { return m_values; }
    bool ready() const { return m_ready; }

    Q_INVOKABLE QVariant value(const QString &key, const QVariant &fallback = QVariant()) const;
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE void reset(const QString &key);

Q_SIGNALS:
    void valuesChanged();
    void changed(const QString &key, const QVariant &value);

private:
    void reload();

    QVariantMap m_values;
    bool m_ready = false;
};

} // namespace astra::qml
