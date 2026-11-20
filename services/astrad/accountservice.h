// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QTimer>

class QNetworkReply;

namespace astrad {

class AlarmService;
class ContactsService;
class HardwareService;
class LocationService;
class NetworkService;
class NotificationService;
class SettingsService;

// AstraID on the phone (the astra cloud server, ro.astra.cloud.url).
//  - Find My Device: the phone reports battery, network and location, and
//    takes commands from the AstraID website (long poll): ring, show a
//    message, lock, locate.
//  - Contacts backup: only the address book (no photos, videos, audio or
//    files), encrypted on the server with a key of the account.
// The session token stays in /data/system/account.json (system only).
//   account.state -> {signedIn, email, name, server, kind, deviceId, findMy, contactsBackup, lastBackup, lastReport}
//   account.signIn {email, password, register?, name?, server?}   account.signOut
//       The device signs in as what it is: a "phone" or, on astraOS Desktop, a "desktop" (astra::Form). AstraID
//       knows both, and Phone Linker and PetalDrop (phonelinkservice.h, petaldropservice.h) use that.
//   account.setFindMy {on}  account.setContactsBackup {on}
//   account.backupNow  account.restoreContacts -> {added}              MANAGE_SETTINGS
//   account.request {method, path, body} -> {status, body}              apps with INTERNET:
//       the app's own API on the AstraID server, /api/app/<package>/..., with this phone's token
class AccountService : public Service
{
    Q_OBJECT
public:
    AccountService(Server *server, SettingsService *settings, NotificationService *notifications,
                   ContactsService *contacts, LocationService *location, HardwareService *hardware,
                   NetworkService *network, AlarmService *alarms, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    void contactsChanged();

    // The AstraID server with this device's token, for the system services that talk to it (Phone Linker,
    // PetalDrop). Apps never get the token: they use account.request.
    QNetworkReply *request(const QByteArray &verb, const QString &path, const QJsonValue &body = QJsonValue());
    bool signedIn() const;
    QString kind() const;                 // "phone" or "desktop"
    int deviceId() const;
    QString userName() const;

Q_SIGNALS:
    void lockRequested(const QString &message);
    // Signed in or out (the account changed): services that follow it start or stop.
    void accountChanged();

private:
    QJsonObject state() const;
    void save();
    void announce();
    QString server() const;
    void startPolling();
    void poll();
    void run(const QJsonObject &command);
    void report(bool withLocation);
    void backup(std::function<void(const QString &error)> done = {});
    void signedOut();

    Server *m_server;
    SettingsService *m_settings;
    NotificationService *m_notifications;
    ContactsService *m_contacts;
    LocationService *m_location;
    HardwareService *m_hardware;
    NetworkService *m_network;
    AlarmService *m_alarms;
    QNetworkAccessManager m_http;
    QString m_path;
    QJsonObject m_account;   // {server, token, deviceId, email, name, findMy, contactsBackup, lastBackup, lastReport}
    QPointer<QNetworkReply> m_poll;
    QTimer m_reportTimer;
    QTimer m_backupTimer;
    QTimer m_retry;
};

} // namespace astrad
