// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJSValue>
#include <QJsonValue>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// Mirrors the state of one astrad service and forwards calls to it.
//
//   Network.state.wifi.powered
//   Network.call("wifiConnect", { ssid: "Home", passphrase: pw }, function(r, err) { ... })
//
// `revision` increases on every event of the service, so views that fetch
// extra data (a conversation, the call log) know when to fetch again.
class ServiceState : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    QVariantMap state() const { return m_state; }
    bool ready() const { return m_ready; }
    int revision() const { return m_revision; }

    // Calls "<service>.<method>"; callback(result, error).
    Q_INVOKABLE void call(const QString &method, const QVariantMap &params = QVariantMap(),
                          const QJSValue &callback = QJSValue());

Q_SIGNALS:
    void stateChanged();
    void revisionChanged();
    void event(const QString &name, const QVariant &data);

protected:
    // service: "network"; stateMethod: "state" (empty: reload() decides);
    // stateEvent: an event that carries the full state.
    ServiceState(const QString &service, const QString &stateMethod, const QString &stateEvent, QObject *parent);
    virtual void reload();
    virtual void onEvent(const QString &name, const QJsonValue &data);
    void setState(const QVariantMap &state);
    void fetch(const QString &method, const QString &key);

    QString m_service;

private:
    QString m_stateMethod;
    QString m_stateEvent;
    QVariantMap m_state;
    bool m_ready = false;
    int m_revision = 0;
};

// Wi-Fi, Bluetooth, mobile data, airplane mode (singleton "Network").
class NetworkState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Network)
    QML_SINGLETON
public:
    explicit NetworkState(QObject *parent = nullptr);
};

// Calls and SMS (singleton "Telephony"). state: { calls: [...] }
class TelephonyState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Telephony)
    QML_SINGLETON
public:
    explicit TelephonyState(QObject *parent = nullptr);
Q_SIGNALS:
    void incoming(const QVariantMap &call);
    void message(const QVariantMap &message);

protected:
    void reload() override;
    void onEvent(const QString &name, const QJsonValue &data) override;
};

// Address book (singleton "Contacts"). state: { contacts: [...] }
class ContactsState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Contacts)
    QML_SINGLETON
public:
    explicit ContactsState(QObject *parent = nullptr);
protected:
    void reload() override;
};

// Alarms and timers (singleton "Alarms"). state: { alarms, timers, next, ringing }
class AlarmsState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Alarms)
    QML_SINGLETON
public:
    explicit AlarmsState(QObject *parent = nullptr);
protected:
    void reload() override;
    void onEvent(const QString &name, const QJsonValue &data) override;
};

// Display modes (singleton "Display"). state: { modes, current, ... }
class DisplayState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Display)
    QML_SINGLETON
public:
    explicit DisplayState(QObject *parent = nullptr);
};

// Software updates (singleton "Updates").
class UpdateState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Updates)
    QML_SINGLETON
public:
    explicit UpdateState(QObject *parent = nullptr);
};

// Developer options and USB debugging (singleton "Developer").
class DeveloperState : public ServiceState
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Developer)
    QML_SINGLETON
public:
    explicit DeveloperState(QObject *parent = nullptr);
};

// Runtime permissions (singleton "Permissions").
//   Permissions.request("astra.permission.CAMERA", function(granted) { ... })
// A request shows the system dialog; if the user allows it the app is
// restarted by the system to pick up the new group, unless `restart` is
// false in which case it keeps running and gains access on next launch.
class PermissionsState : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Permissions)
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY changed)
public:
    explicit PermissionsState(QObject *parent = nullptr);
    int revision() const { return m_revision; }

    Q_INVOKABLE void check(const QString &permission, const QJSValue &callback);
    Q_INVOKABLE void request(const QString &permission, const QJSValue &callback = QJSValue());
    // Settings: catalog() -> [{name, label, icon, level}], forPackage(pkg) -> [{name, granted, ...}]
    Q_INVOKABLE void catalog(const QJSValue &callback);
    Q_INVOKABLE void forPackage(const QString &package, const QJSValue &callback);
    Q_INVOKABLE void apps(const QString &permission, const QJSValue &callback);
    // state: "granted", "denied" or "ask"
    Q_INVOKABLE void set(const QString &package, const QString &permission, const QString &state,
                         const QJSValue &callback = QJSValue());

Q_SIGNALS:
    void changed();

private:
    int m_revision = 0;
};

// Bottom sheet dialogs (singleton "Dialogs").
//   Dialogs.show({ title: "Delete?", message: "...", buttons: [{id: "no", label: "Cancel"},
//                 {id: "yes", label: "Delete", style: "destructive"}] }, function(button) { ... })
// The first button is the cancel action. SysBoard presents them; it also
// uses pending()/answer() and the shown/closed signals.
class DialogsState : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Dialogs)
    QML_SINGLETON
public:
    explicit DialogsState(QObject *parent = nullptr);

    Q_INVOKABLE void show(const QVariantMap &dialog, const QJSValue &callback = QJSValue());
    Q_INVOKABLE void answer(int id, const QString &button);
    Q_INVOKABLE void pending(const QJSValue &callback);

Q_SIGNALS:
    void shown(const QVariantMap &dialog);
    void closed(int id);
};

// UI language (singleton "Language").
class LanguageState : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Language)
    QML_SINGLETON
    Q_PROPERTY(QString current READ current NOTIFY changed)
    Q_PROPERTY(QVariantList available READ available CONSTANT)
public:
    explicit LanguageState(QObject *parent = nullptr);
    QString current() const;
    QVariantList available() const;
    Q_INVOKABLE void set(const QString &code);
    Q_INVOKABLE QString nameOf(const QString &code) const;

Q_SIGNALS:
    void changed();
};

// Fonts installed in /system/fonts (singleton "Fonts").
class FontsState : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Fonts)
    QML_SINGLETON
    Q_PROPERTY(QStringList families READ families CONSTANT)
public:
    explicit FontsState(QObject *parent = nullptr);
    // Every family except Poppins, which is offered with a weight slider.
    QStringList families() const { return m_families; }

private:
    QStringList m_families;
};

} // namespace astra::qml
