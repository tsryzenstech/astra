// SPDX-License-Identifier: Apache-2.0
#include "phonelinkservice.h"
#include "accountservice.h"
#include "contactsservice.h"
#include "notificationservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/form.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QNetworkReply>

Q_LOGGING_CATEGORY(lcLink, "astrad.phonelink")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
constexpr qint64 kMaxPhoto = 12 * 1024 * 1024;
const QString kMirrorPackage = QStringLiteral("com.astra.astraid"); // where a notification of the other device is shown
} // namespace

PhoneLinkService::PhoneLinkService(Server *server, SettingsService *settings, AccountService *account,
                                   NotificationService *notifications, ContactsService *contacts, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_account(account)
    , m_notifications(notifications)
    , m_contacts(contacts)
{
    m_retry.setSingleShot(true);
    m_retry.setInterval(30 * 1000);
    connect(&m_retry, &QTimer::timeout, this, [this] { refreshLink(); });
    m_contactsTimer.setSingleShot(true);
    m_contactsTimer.setInterval(4000);
    connect(&m_contactsTimer, &QTimer::timeout, this, &PhoneLinkService::sendContacts);
    m_photoTimer.setInterval(15 * 1000);
    connect(&m_photoTimer, &QTimer::timeout, this, &PhoneLinkService::scanPhotos);

    connect(m_account, &AccountService::accountChanged, this, [this] { m_link = {}; refreshLink(); });
    connect(m_notifications, &NotificationService::posted, this, &PhoneLinkService::onNotification);
    connect(m_settings, &SettingsService::changed, this, [this](const QString &key, const QJsonValue &) {
        if (!key.startsWith(QLatin1String("phonelinker.")))
            return;
        if (key == QLatin1String("phonelinker.photos") && wanted("photos"))
            m_settings->setValue(K("phonelinker.last_photo"), double(QDateTime::currentMSecsSinceEpoch())); // no history
        reconfigure();
        announce();
    });
    QTimer::singleShot(8000, this, [this] { refreshLink(); });
}

bool PhoneLinkService::wanted(const char *feature) const
{
    return m_settings->value(K("phonelinker.enabled")).toBool(false)
        && m_settings->value(K("phonelinker.") + K(feature)).toBool(true);
}

bool PhoneLinkService::active() const
{
    return m_account->signedIn() && m_settings->value(K("phonelinker.enabled")).toBool(false) && m_link.value(K("linked")).toBool();
}

QJsonObject PhoneLinkService::state() const
{
    return {{K("kind"), m_account->kind()},
            {K("signedIn"), m_account->signedIn()},
            {K("enabled"), m_settings->value(K("phonelinker.enabled")).toBool(false)},
            {K("linked"), m_link.value(K("linked")).toBool()},
            {K("peer"), m_link.value(K("peer"))},
            {K("candidates"), m_link.value(K("candidates"))},
            {K("features"), QJsonObject{{K("notifications"), m_settings->value(K("phonelinker.notifications")).toBool(true)},
                                        {K("contacts"), m_settings->value(K("phonelinker.contacts")).toBool(true)},
                                        {K("photos"), m_settings->value(K("phonelinker.photos")).toBool(true)}}},
            {K("lastSync"), m_lastSync},
            {K("error"), m_error}};
}

void PhoneLinkService::announce()
{
    m_server->broadcast(K("phonelink.changed"), state(),
                        [](const Caller &c) { return c.can(QLatin1String(permissions::MANAGE_SETTINGS)); });
}

void PhoneLinkService::refreshLink(std::function<void(const QString &)> done)
{
    if (!m_account->signedIn()) {
        m_link = {};
        m_error.clear();
        reconfigure();
        announce();
        if (done)
            done(QString());
        return;
    }
    QNetworkReply *reply = m_account->request("GET", K("/api/device/link"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError && reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 0) {
            m_error = reply->errorString();
            m_retry.start();
        } else {
            const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
            if (reply->error() != QNetworkReply::NoError) {
                m_error = r.value(K("error")).toString(reply->errorString());
            } else {
                m_error.clear();
                m_link = r;
            }
        }
        reconfigure();
        announce();
        if (done)
            done(m_error);
    });
}

// Starts or stops the long poll and the photo watcher with the link and the switches.
void PhoneLinkService::reconfigure()
{
    if (active()) {
        if (!m_poll)
            poll();
        if (m_account->kind() == QLatin1String("phone") && wanted("photos"))
            m_photoTimer.start();
        else
            m_photoTimer.stop();
    } else {
        if (m_poll)
            m_poll->abort();
        m_photoTimer.stop();
    }
}

void PhoneLinkService::poll()
{
    if (m_poll || !active())
        return;
    QNetworkReply *reply = m_account->request("GET", QStringLiteral("/api/link/events?after=%1&wait=55").arg(m_after));
    m_poll = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError) {
            if (reply->error() == QNetworkReply::OperationCanceledError)
                return;
            if (status == 409 || status == 404) {   // not linked any more
                refreshLink();
                return;
            }
            m_retry.start();
            return;
        }
        for (const QJsonValue &v : QJsonDocument::fromJson(reply->readAll()).array()) {
            const QJsonObject e = v.toObject();
            m_after = qMax<qint64>(m_after, qint64(e.value(K("id")).toDouble()));
            handleEvent(e);
        }
        QTimer::singleShot(150, this, &PhoneLinkService::poll);
    });
}

void PhoneLinkService::handleEvent(const QJsonObject &event)
{
    const QString kind = event.value(K("kind")).toString();
    const QJsonObject p = event.value(K("payload")).toObject();
    m_lastSync = double(QDateTime::currentMSecsSinceEpoch());
    if (kind == QLatin1String("notification")) {
        if (!m_settings->value(K("phonelinker.notifications")).toBool(true))
            return;
        const QString app = p.value(K("app")).toString();
        const QString title = p.value(K("title")).toString();
        // Shown as it came: the phone's app and what it said. Opening it does not open an app here.
        m_notifications->post(kMirrorPackage, app.isEmpty() ? title : QStringLiteral("%1: %2").arg(app, title),
                              p.value(K("body")).toString(), QJsonObject{{K("fromPhone"), true}});
    } else if (kind == QLatin1String("contacts")) {
        if (!m_settings->value(K("phonelinker.contacts")).toBool(true))
            return;
        m_applying = true;
        const int added = m_contacts->merge(p.value(K("contacts")).toArray());
        m_applying = false;
        qCInfo(lcLink) << "contacts from the linked device:" << added << "new";
    } else if (kind == QLatin1String("photo")) {
        if (!m_settings->value(K("phonelinker.photos")).toBool(true))
            return;
        const QString name = QFileInfo(p.value(K("name")).toString()).fileName();   // no path
        const QByteArray data = QByteArray::fromBase64(p.value(K("data")).toString().toLatin1());
        if (name.isEmpty() || name.startsWith(QLatin1Char('.')) || data.isEmpty() || data.size() > kMaxPhoto)
            return;
        const QString dir = Paths::userMedia() + QStringLiteral("/Pictures/Phone");
        QDir().mkpath(dir);
        QString target = dir + QLatin1Char('/') + name;
        for (int i = 1; QFile::exists(target); ++i)
            target = dir + QLatin1Char('/') + QFileInfo(name).completeBaseName() + QStringLiteral("_%1.").arg(i) + QFileInfo(name).suffix();
        QFile f(target);
        if (f.open(QIODevice::WriteOnly)) {
            f.write(data);
            f.close();
            qCInfo(lcLink) << "photo from the linked device:" << target;
        }
    } else if (kind == QLatin1String("dismiss")) {
        // Reserved: a notification dismissed on the phone going away here.
    }
    announce();
}

void PhoneLinkService::send(const QString &kind, const QJsonObject &payload)
{
    if (!active())
        return;
    QNetworkReply *reply = m_account->request("POST", K("/api/link/send"), QJsonObject{{K("kind"), kind}, {K("payload"), payload}});
    connect(reply, &QNetworkReply::finished, this, [this, reply, kind] {
        reply->deleteLater();
        if (reply->error() == QNetworkReply::NoError) {
            m_lastSync = double(QDateTime::currentMSecsSinceEpoch());
            announce();
        } else {
            qCWarning(lcLink) << "sending" << kind << "failed:" << reply->errorString();
        }
    });
}

void PhoneLinkService::onNotification(const QJsonObject &n)
{
    // The phone shows its notifications on the desktop; what the desktop shows stays there.
    if (m_account->kind() != QLatin1String("phone") || !active() || !wanted("notifications"))
        return;
    if (n.value(K("package")).toString() == kMirrorPackage || n.value(K("ongoing")).toBool())
        return;
    send(K("notification"), QJsonObject{{K("app"), n.value(K("appName")).toString()},
                                        {K("title"), n.value(K("title")).toString()},
                                        {K("body"), n.value(K("body")).toString()},
                                        {K("time"), n.value(K("time"))}});
}

void PhoneLinkService::contactsChanged()
{
    if (!m_applying && active() && wanted("contacts"))
        m_contactsTimer.start();
}

void PhoneLinkService::sendContacts()
{
    if (!active() || !wanted("contacts"))
        return;
    QJsonArray list;
    for (const QJsonValue &v : m_contacts->all()) {
        QJsonObject c = v.toObject();
        c.remove(K("id"));
        list.append(c);
    }
    send(K("contacts"), QJsonObject{{K("contacts"), list}});
}

// New pictures since the last look (or since the switch was turned on) go to the desktop.
void PhoneLinkService::scanPhotos()
{
    if (!active() || !wanted("photos"))
        return;
    const qint64 since = qint64(m_settings->value(K("phonelinker.last_photo")).toDouble());
    qint64 newest = since;
    int sent = 0;
    for (const char *sub : {"DCIM/Camera", "Pictures"}) {
        QDirIterator it(Paths::userMedia() + QLatin1Char('/') + K(sub), {K("*.jpg"), K("*.jpeg"), K("*.png")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext() && sent < 5) {
            const QFileInfo info(it.next());
            if (info.absoluteFilePath().contains(QLatin1String("/Pictures/Phone/")) || info.absoluteFilePath().contains(QLatin1String("/Screenshots/")))
                continue;
            const qint64 t = info.lastModified().toMSecsSinceEpoch();
            if (t <= since || info.size() > kMaxPhoto || info.size() == 0)
                continue;
            QFile f(info.absoluteFilePath());
            if (!f.open(QIODevice::ReadOnly))
                continue;
            send(K("photo"), QJsonObject{{K("name"), info.fileName()}, {K("time"), double(t)},
                                         {K("data"), QString::fromLatin1(f.readAll().toBase64())}});
            newest = qMax(newest, t);
            ++sent;
        }
    }
    if (newest > since)
        m_settings->setValue(K("phonelinker.last_photo"), double(newest));
}

QJsonValue PhoneLinkService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("refresh")) {
        const PendingReply pending = caller.defer();
        refreshLink([this, pending](const QString &error) {
            if (error.isEmpty())
                pending.resolve(state());
            else
                pending.reject(protocol::Failed, error);
        });
        return Deferred;
    }
    if (call == QLatin1String("link")) {
        const PendingReply pending = caller.defer();
        QNetworkReply *reply = m_account->request("POST", K("/api/device/link"), QJsonObject{{K("peer"), params.value(K("peer"))}});
        connect(reply, &QNetworkReply::finished, this, [this, reply, pending] {
            reply->deleteLater();
            const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
            if (reply->error() != QNetworkReply::NoError) {
                pending.reject(protocol::Failed, r.value(K("error")).toString(reply->errorString()));
                return;
            }
            m_settings->setValue(K("phonelinker.enabled"), true);
            m_settings->setValue(K("phonelinker.last_photo"), double(QDateTime::currentMSecsSinceEpoch()));
            refreshLink([this, pending](const QString &error) {
                if (error.isEmpty()) {
                    pending.resolve(state());
                    sendContacts();
                } else {
                    pending.reject(protocol::Failed, error);
                }
            });
        });
        return Deferred;
    }
    if (call == QLatin1String("unlink")) {
        const PendingReply pending = caller.defer();
        QNetworkReply *reply = m_account->request("DELETE", K("/api/device/link"));
        connect(reply, &QNetworkReply::finished, this, [this, reply, pending] {
            reply->deleteLater();
            m_after = 0;
            refreshLink([this, pending](const QString &) { pending.resolve(state()); });
        });
        return Deferred;
    }
    if (call == QLatin1String("syncNow")) {
        sendContacts();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
