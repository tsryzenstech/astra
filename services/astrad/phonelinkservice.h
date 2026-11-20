// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QElapsedTimer>
#include <QJsonObject>
#include <QPointer>
#include <QTimer>

class QNetworkReply;

namespace astrad {

class AccountService;
class ContactsService;
class NotificationService;
class SettingsService;

// Phone Linker: a phone and a desktop of one AstraID, linked, share their contacts, the phone's photos and
// notifications as they happen (docs/DESKTOP.md). A phone is linked with one desktop and the other way round:
// the AstraID server keeps the link and carries what one side sends the other (astra-cloud lib/link.js, a long
// poll, so a notification is on the desktop within a second or two).
//
//   phonelink.state                 -> {kind, enabled, linked, peer, candidates, features, lastSync, error}
//   phonelink.refresh               -> state, asking the server
//   phonelink.link {peer}           link with one of `candidates` (a device of the other kind)
//   phonelink.unlink
//   phonelink.syncNow               send the contacts now
// The switches are settings (Settings > Phone Linker writes them): "phonelinker.enabled",
// "phonelinker.notifications", "phonelinker.contacts", "phonelinker.photos".    MANAGE_SETTINGS
//
// Phone to desktop: notifications (not ongoing ones, not the system's own) and new photos (DCIM/Camera and
// Pictures, up to 12 MB each, from the moment the link was turned on). Both ways: the contacts (each side adds
// what it lacks). The desktop shows the phone's notifications in its Notification Center and puts the photos in
// Pictures/Phone.
class PhoneLinkService : public Service
{
    Q_OBJECT
public:
    PhoneLinkService(Server *server, SettingsService *settings, AccountService *account,
                     NotificationService *notifications, ContactsService *contacts, QObject *parent = nullptr);
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    // The address book changed (ContactsService hook).
    void contactsChanged();

private:
    bool wanted(const char *feature) const;
    bool active() const;
    QJsonObject state() const;
    void announce();
    void refreshLink(std::function<void(const QString &error)> done = {});
    void reconfigure();
    void poll();
    void handleEvent(const QJsonObject &event);
    void send(const QString &kind, const QJsonObject &payload);
    void sendContacts();
    void scanPhotos();
    void onNotification(const QJsonObject &n);

    Server *m_server;
    SettingsService *m_settings;
    AccountService *m_account;
    NotificationService *m_notifications;
    ContactsService *m_contacts;

    QJsonObject m_link;           // the server's answer to GET /api/device/link
    QString m_error;
    double m_lastSync = 0;
    qint64 m_after = 0;           // the last event received (and acknowledged with the next poll)
    bool m_applying = false;      // merging received contacts: not a change to send back
    QPointer<QNetworkReply> m_poll;
    QTimer m_retry;
    QTimer m_contactsTimer;
    QTimer m_photoTimer;
};

} // namespace astrad
