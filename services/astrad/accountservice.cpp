// SPDX-License-Identifier: Apache-2.0
#include "accountservice.h"
#include "alarmservice.h"
#include "contactsservice.h"
#include "hardwareservice.h"
#include "jsonstore.h"
#include "locationservice.h"
#include "network/networkservice.h"
#include "notificationservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QNetworkReply>
#include <QSysInfo>

Q_LOGGING_CATEGORY(lcAccount, "astrad.account")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
QString errorOf(QNetworkReply *reply, const QJsonObject &body)
{
    const QString e = body.value(QLatin1String("error")).toString();
    if (!e.isEmpty())
        return e.left(1).toUpper() + e.mid(1);
    return reply->error() == QNetworkReply::NoError ? QString() : reply->errorString();
}
} // namespace

AccountService::AccountService(Server *server, SettingsService *settings, NotificationService *notifications,
                               ContactsService *contacts, LocationService *location, HardwareService *hardware,
                               NetworkService *network, AlarmService *alarms, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_contacts(contacts)
    , m_location(location)
    , m_hardware(hardware)
    , m_network(network)
    , m_alarms(alarms)
    , m_path(Paths::dataSystem() + QStringLiteral("/account.json"))
{
    m_account = loadJson(m_path);
    m_reportTimer.setInterval(15 * 60 * 1000);
    connect(&m_reportTimer, &QTimer::timeout, this, [this] { report(true); });
    m_backupTimer.setSingleShot(true);
    m_backupTimer.setInterval(60 * 1000);
    connect(&m_backupTimer, &QTimer::timeout, this, [this] { backup(); });
    m_retry.setSingleShot(true);
    m_retry.setInterval(30 * 1000);
    connect(&m_retry, &QTimer::timeout, this, &AccountService::poll);
    if (!m_account.value(K("token")).toString().isEmpty()) {
        m_reportTimer.start();
        QTimer::singleShot(5000, this, [this] { report(true); startPolling(); });
    }
}

QString AccountService::server() const
{
    const QString s = m_account.value(K("server")).toString();
    if (!s.isEmpty())
        return s;
    return Properties::get(K("ro.astra.cloud.url"), K("http://34.155.86.153"));
}

QJsonObject AccountService::state() const
{
    const bool in = !m_account.value(K("token")).toString().isEmpty();
    return {{K("signedIn"), in},
            {K("email"), m_account.value(K("email"))},
            {K("name"), m_account.value(K("name"))},
            {K("server"), server()},
            {K("findMy"), m_account.value(K("findMy")).toBool(true)},
            {K("contactsBackup"), m_account.value(K("contactsBackup")).toBool(true)},
            {K("lastBackup"), m_account.value(K("lastBackup"))},
            {K("lastReport"), m_account.value(K("lastReport"))}};
}

void AccountService::save()
{
    saveJson(m_path, m_account);
    QFile::setPermissions(m_path, QFile::ReadOwner | QFile::WriteOwner);
}

void AccountService::announce()
{
    m_server->broadcast(K("account.changed"), state(),
                        [](const Caller &c) { return c.can(QLatin1String(permissions::MANAGE_SETTINGS)); });
}

QNetworkReply *AccountService::request(const QByteArray &verb, const QString &path, const QJsonValue &body)
{
    QNetworkRequest req{QUrl(server() + path)};
    req.setHeader(QNetworkRequest::ContentTypeHeader, K("application/json"));
    const QString token = m_account.value(K("token")).toString();
    if (!token.isEmpty())
        req.setRawHeader("Authorization", "Bearer " + token.toUtf8());
    if (!path.startsWith(QLatin1String("/api/device/commands?")))
        req.setTransferTimeout(30000);
    QByteArray data;
    if (!body.isUndefined())
        data = body.isArray() ? QJsonDocument(body.toArray()).toJson(QJsonDocument::Compact)
                              : QJsonDocument(body.toObject()).toJson(QJsonDocument::Compact);
    return m_http.sendCustomRequest(req, verb, data);
}

// The server answers 401 once the phone was removed from AstraID.
void AccountService::signedOut()
{
    if (m_poll)
        m_poll->abort();
    m_reportTimer.stop();
    m_retry.stop();
    const QString server = m_account.value(K("server")).toString();
    m_account = {};
    if (!server.isEmpty())
        m_account.insert(K("server"), server);
    save();
    announce();
}

void AccountService::startPolling()
{
    if (m_poll || m_account.value(K("token")).toString().isEmpty() || !m_account.value(K("findMy")).toBool(true))
        return;
    poll();
}

// Waits up to 55 seconds for commands from the AstraID website.
void AccountService::poll()
{
    if (m_poll || m_account.value(K("token")).toString().isEmpty() || !m_account.value(K("findMy")).toBool(true))
        return;
    QNetworkReply *reply = request("GET", K("/api/device/commands?wait=55"));
    m_poll = reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 401) {
            signedOut();
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            if (reply->error() != QNetworkReply::OperationCanceledError)
                m_retry.start();
            return;
        }
        for (const QJsonValue &c : QJsonDocument::fromJson(reply->readAll()).array())
            run(c.toObject());
        QTimer::singleShot(200, this, &AccountService::poll);
    });
}

void AccountService::run(const QJsonObject &command)
{
    const QString type = command.value(K("type")).toString();
    const int id = command.value(K("id")).toInt();
    QString result = K("done");
    qCInfo(lcAccount) << "Find My Device:" << type;
    if (type == QLatin1String("ring")) {
        m_alarms->ringNow(K("findmy"), K("Find My Device"));
    } else if (type == QLatin1String("notify")) {
        m_notifications->post(K("com.astra.astraid"), command.value(K("title")).toString(), command.value(K("body")).toString());
    } else if (type == QLatin1String("lock")) {
        const QString message = command.value(K("body")).toString();
        Q_EMIT lockRequested(message);
        if (!message.isEmpty())
            m_notifications->post(K("com.astra.astraid"), command.value(K("title")).toString(), message);
    } else if (type == QLatin1String("locate")) {
        report(true);
        result = m_location->enabled() ? K("locating") : K("Location Services are off");
    } else {
        result = K("unknown command");
    }
    QNetworkReply *ack = request("POST", QStringLiteral("/api/device/commands/%1/ack").arg(id), QJsonObject{{K("result"), result}});
    connect(ack, &QNetworkReply::finished, ack, &QObject::deleteLater);
}

void AccountService::report(bool withLocation)
{
    if (m_account.value(K("token")).toString().isEmpty())
        return;
    const QJsonObject battery = m_hardware->battery();
    const QJsonObject net = m_network->state();
    const QJsonObject wifi = net.value(K("wifi")).toObject();
    const QJsonObject cell = net.value(K("cellular")).toObject();
    QJsonObject body{
        {K("findMy"), m_account.value(K("findMy")).toBool(true)},
        {K("os"), QStringLiteral("astraOS %1").arg(Properties::get(K("ro.astra.version")))},
        {K("network"), wifi.value(K("state")).toString() == QLatin1String("connected") ? wifi.value(K("ssid")).toString()
                                                                                         : cell.value(K("operator")).toString()},
    };
    if (battery.value(K("present")).toBool(true) && battery.contains(K("level"))) {
        body.insert(K("battery"), battery.value(K("level")).toInt());
        body.insert(K("charging"), battery.value(K("charging")).toBool());
    }
    auto send = [this](const QJsonObject &b) {
        QNetworkReply *reply = request("POST", K("/api/device/report"), b);
        connect(reply, &QNetworkReply::finished, this, [this, reply] {
            reply->deleteLater();
            if (reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() == 401) {
                signedOut();
                return;
            }
            if (reply->error() == QNetworkReply::NoError) {
                m_account.insert(K("lastReport"), double(QDateTime::currentMSecsSinceEpoch()));
                save();
            }
        });
    };
    if (!withLocation || !m_account.value(K("findMy")).toBool(true) || !m_location->enabled()) {
        send(body);
        return;
    }
    m_location->locate([send, body](const QJsonObject &fix) mutable {
        if (!fix.isEmpty())
            body.insert(K("location"), fix);
        send(body);
    });
}

void AccountService::contactsChanged()
{
    if (!m_account.value(K("token")).toString().isEmpty() && m_account.value(K("contactsBackup")).toBool(true))
        m_backupTimer.start();
}

void AccountService::backup(std::function<void(const QString &)> done)
{
    QJsonArray contacts;
    for (const QJsonValue &v : m_contacts->all()) {
        QJsonObject c = v.toObject();
        c.remove(K("id"));
        contacts.append(c);
    }
    QNetworkReply *reply = request("PUT", K("/api/device/contacts"), QJsonObject{{K("contacts"), contacts}});
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        const QString error = errorOf(reply, QJsonDocument::fromJson(reply->readAll()).object());
        if (error.isEmpty()) {
            m_account.insert(K("lastBackup"), double(QDateTime::currentMSecsSinceEpoch()));
            save();
            announce();
        }
        if (done)
            done(error);
    });
}

QJsonValue AccountService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
    if (call == QLatin1String("state"))
        return state();

    if (call == QLatin1String("signIn")) {
        QString url = params.value(K("server")).toString().trimmed();
        if (!url.isEmpty()) {
            if (!url.contains(QLatin1String("://")))
                url.prepend(QStringLiteral("http://"));
            m_account.insert(K("server"), url.endsWith(QLatin1Char('/')) ? url.chopped(1) : url);
        }
        const bool reg = params.value(K("register")).toBool();
        const QJsonObject body{
            {K("email"), params.value(K("email")).toString().trimmed()},
            {K("password"), params.value(K("password")).toString()},
            {K("name"), params.value(K("name")).toString()},
            {K("device"), QJsonObject{{K("name"), m_settings->value(K("account.name")).toString().isEmpty()
                                                     ? Properties::get(K("ro.product.model"), K("astraOS phone"))
                                                     : QStringLiteral("%1's phone").arg(m_settings->value(K("account.name")).toString())},
                                      {K("model"), Properties::get(K("ro.product.model"), QSysInfo::machineHostName())},
                                      {K("os"), QStringLiteral("astraOS %1").arg(Properties::get(K("ro.astra.version")))}}}};
        m_account.remove(K("token"));
        const PendingReply pending = caller.defer();
        QNetworkReply *reply = request("POST", reg ? K("/api/auth/register") : K("/api/auth/login"), body);
        connect(reply, &QNetworkReply::finished, this, [this, reply, pending] {
            reply->deleteLater();
            const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
            const QString error = errorOf(reply, r);
            if (!error.isEmpty() || r.value(K("token")).toString().isEmpty()) {
                pending.reject(protocol::Failed, error.isEmpty() ? K("The AstraID server did not answer") : error);
                return;
            }
            const QJsonObject user = r.value(K("user")).toObject();
            m_account.insert(K("token"), r.value(K("token")));
            m_account.insert(K("deviceId"), r.value(K("deviceId")));
            m_account.insert(K("email"), user.value(K("email")));
            m_account.insert(K("name"), user.value(K("name")));
            save();
            if (m_settings->value(K("account.name")).toString().isEmpty())
                m_settings->setValue(K("account.name"), user.value(K("name")).toString());
            m_reportTimer.start();
            report(true);
            startPolling();
            if (m_account.value(K("contactsBackup")).toBool(true))
                backup();
            announce();
            pending.resolve(state());
        });
        return Deferred;
    }
    if (call == QLatin1String("signOut")) {
        QNetworkReply *reply = request("POST", K("/api/auth/logout"), QJsonObject());
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
        signedOut();
        return true;
    }
    if (call == QLatin1String("setFindMy") || call == QLatin1String("setContactsBackup")) {
        const bool on = params.value(K("on")).toBool();
        m_account.insert(call == QLatin1String("setFindMy") ? K("findMy") : K("contactsBackup"), on);
        save();
        if (call == QLatin1String("setFindMy")) {
            report(on);
            if (on)
                startPolling();
            else if (m_poll)
                m_poll->abort();
        } else if (on) {
            backup();
        }
        announce();
        return state();
    }
    if (call == QLatin1String("backupNow")) {
        const PendingReply pending = caller.defer();
        backup([pending, this](const QString &error) {
            if (error.isEmpty())
                pending.resolve(state());
            else
                pending.reject(protocol::Failed, error);
        });
        return Deferred;
    }
    if (call == QLatin1String("restoreContacts")) {
        const PendingReply pending = caller.defer();
        QNetworkReply *reply = request("GET", K("/api/device/contacts"));
        connect(reply, &QNetworkReply::finished, this, [this, reply, pending] {
            reply->deleteLater();
            const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
            const QString error = errorOf(reply, r);
            if (!error.isEmpty()) {
                pending.reject(protocol::Failed, error);
                return;
            }
            const int added = m_contacts->merge(r.value(K("contacts")).toArray());
            pending.resolve(QJsonObject{{K("added"), added}});
        });
        return Deferred;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
