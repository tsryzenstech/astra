// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJSValue>
#include <QObject>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// System state and hardware controls (QML singleton "System").
class SystemInfo : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(System)
    QML_SINGLETON

    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QVariantMap info READ info NOTIFY infoChanged)
    Q_PROPERTY(int batteryLevel READ batteryLevel NOTIFY hardwareChanged)
    Q_PROPERTY(bool charging READ charging NOTIFY hardwareChanged)
    Q_PROPERTY(qreal brightness READ brightness NOTIFY hardwareChanged)
    Q_PROPERTY(bool torch READ torch NOTIFY hardwareChanged)
    Q_PROPERTY(bool torchAvailable READ torchAvailable NOTIFY hardwareChanged)
    // level, charging, status, health, temperature, voltage, ... (Settings > Battery)
    Q_PROPERTY(QVariantMap battery READ battery NOTIFY hardwareChanged)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    bool connected() const;
    QVariantMap info() const { return m_info; }
    int batteryLevel() const;
    bool charging() const;
    qreal brightness() const { return m_hw.value(QStringLiteral("brightness")).toReal(); }
    bool torch() const { return m_hw.value(QStringLiteral("torch")).toBool(); }
    bool torchAvailable() const { return m_hw.value(QStringLiteral("torchAvailable")).toBool(); }
    QVariantMap battery() const { return m_hw.value(QStringLiteral("battery")).toMap(); }
    QString version() const;

    Q_INVOKABLE void setBrightness(qreal value);
    Q_INVOKABLE void setTorch(bool on);
    // "reboot", "poweroff", "bootloader", "recovery", "restart-sysboard"
    Q_INVOKABLE void power(const QString &action, const QJSValue &callback = QJSValue());
    Q_INVOKABLE void setScreen(bool on);
    // Saves a PNG of the screen to Pictures/Screenshots (SysBoard does the capture).
    Q_INVOKABLE void screenshot(const QJSValue &callback = QJSValue());
    Q_INVOKABLE void markBootCompleted();
    Q_INVOKABLE QString property(const QString &key, const QString &fallback = QString()) const;
    // file:// URL of a system path, e.g. System.fileUrl("/system/media/brand/astra_white.svg")
    Q_INVOKABLE QUrl fileUrl(const QString &path) const;
    // Files in a system directory, as system paths, e.g. System.files("/system/media/wallpapers", ["*.png"])
    Q_INVOKABLE QStringList files(const QString &dir, const QStringList &nameFilters = {}) const;
    // Raw access to astrad for diagnostics and tests.
    Q_INVOKABLE void call(const QString &method, const QVariantMap &params, const QJSValue &callback);

Q_SIGNALS:
    void connectedChanged();
    void infoChanged();
    void hardwareChanged();
    void bootCompleted();

private:
    void reload();

    QVariantMap m_info;
    QVariantMap m_hw;
};

} // namespace astra::qml
