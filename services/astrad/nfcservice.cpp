// SPDX-License-Identifier: Apache-2.0
#include "nfcservice.h"
#include "nfc/ndef.h"
#include "nfc/nfcadapter.h"
#include "notificationservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QJsonArray>
#include <QUrl>

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
const char kSetting[] = "controls.nfc";
constexpr int kWriteWaitMs = 60000;
} // namespace

NfcService::NfcService(Server *server, SettingsService *settings, NotificationService *notifications, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_adapter(new nfc::NfcAdapter)
{
    m_adapter->moveToThread(&m_thread);
    connect(&m_thread, &QThread::finished, m_adapter, &QObject::deleteLater);
    connect(m_adapter, &nfc::NfcAdapter::stateChanged, this, [this](bool available, bool on) {
        m_available = available;
        m_on = on;
        changed();
    });
    connect(m_adapter, &nfc::NfcAdapter::tagRead, this, &NfcService::onTag);
    connect(m_adapter, &nfc::NfcAdapter::writeFinished, this, &NfcService::endWrite);
    connect(m_settings, &SettingsService::changed, this, [this](const QString &key) {
        if (key == QLatin1String(kSetting)) {
            QMetaObject::invokeMethod(m_adapter, "setEnabled", Qt::QueuedConnection, Q_ARG(bool, wanted()));
            changed();
        }
    });
    m_writeTimeout.setSingleShot(true);
    m_writeTimeout.setInterval(kWriteWaitMs);
    connect(&m_writeTimeout, &QTimer::timeout, this, [this] {
        QMetaObject::invokeMethod(m_adapter, "setPendingWrite", Qt::QueuedConnection, Q_ARG(QByteArray, QByteArray()));
        endWrite(false, K("No tag was held to the phone"));
    });

    // A development tree has no phone under it.
    if (Paths::isDevelopmentRoot())
        return;
    m_thread.setObjectName(K("nfc"));
    m_thread.start();
    QMetaObject::invokeMethod(m_adapter, "setEnabled", Qt::QueuedConnection, Q_ARG(bool, wanted()));
    QMetaObject::invokeMethod(m_adapter, "start", Qt::QueuedConnection);
}

NfcService::~NfcService()
{
    if (m_thread.isRunning()) {
        m_thread.quit();
        m_thread.wait(25000);
    } else {
        delete m_adapter;
    }
}

bool NfcService::wanted() const
{
    return m_settings->value(QLatin1String(kSetting)).toBool();
}

QJsonObject NfcService::state() const
{
    return {{K("available"), m_available}, {K("enabled"), wanted()}, {K("on"), m_on},
            {K("tag"), m_tag}, {K("write"), m_write}};
}

void NfcService::changed()
{
    m_server->broadcast(K("nfc.changed"), state(),
                        [](const Caller &c) { return c.can(QLatin1String(permissions::MANAGE_NETWORK)); });
}

void NfcService::endWrite(bool ok, const QString &error)
{
    m_writeTimeout.stop();
    m_write = QJsonObject{{K("waiting"), false}, {K("ok"), ok}, {K("error"), error}};
    changed();
}

void NfcService::onTag(const QJsonObject &read)
{
    QJsonObject tag = read;
    tag.insert(K("time"), double(QDateTime::currentMSecsSinceEpoch()));
    m_tag = tag;
    changed();
    m_server->broadcast(K("nfc.tag"), tag,
                        [](const Caller &c) { return c.can(QLatin1String(permissions::MANAGE_NETWORK)); });
    // Told once a visit, and not for a tag just written from Settings, which shows it.
    if (!tag.value(K("repeat")).toBool() && !tag.value(K("written")).toBool() && !tag.value(K("empty")).toBool())
        notify(tag);
}

void NfcService::notify(const QJsonObject &tag)
{
    if (!m_notifications)
        return;
    const QJsonArray records = tag.value(K("records")).toArray();
    const QString what = nfc::summary(records);
    if (what.isEmpty() && records.isEmpty())
        return;
    const bool it = m_settings->value(K("system.language")).toString().startsWith(QLatin1String("it"));

    // The app that opens what the tag says; Settings shows everything else.
    QString package = K("com.astra.settings");
    QJsonObject args{{K("page"), K("nfc")}};
    QString body = what;
    const QUrl url(what);
    const QString scheme = url.scheme().toLower();
    if (scheme == QLatin1String("http") || scheme == QLatin1String("https")) {
        package = K("com.astra.planet");
        args = QJsonObject{{K("url"), what}};
    } else if (scheme == QLatin1String("tel")) {
        package = K("com.astra.phone");
        args = QJsonObject{{K("dial"), url.path()}};
        body = url.path();
    } else if (scheme == QLatin1String("mailto")) {
        package = K("com.astra.email");
        args = QJsonObject{{K("to"), url.path()}};
        body = url.path();
    } else if (scheme == QLatin1String("sms") || scheme == QLatin1String("smsto")) {
        package = K("com.astra.messages");
        args = QJsonObject{{K("number"), url.path()}};
        body = url.path();
    } else if (scheme == QLatin1String("geo")) {
        package = K("com.astra.maps");
        args = QJsonObject{{K("query"), url.path().section(QLatin1Char(';'), 0, 0)}};
    } else if (what.isEmpty()) {
        const QJsonObject first = records.first().toObject();
        body = first.value(K("type")).toString();
    }
    if (m_notification)
        m_notifications->dismissId(m_notification);
    m_notification = m_notifications->post(package, it ? K("Tag NFC") : K("NFC tag"), body, QJsonObject{{K("args"), args}});
}

QJsonValue NfcService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::MANAGE_NETWORK));
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("write")) {
        if (!m_available || !m_on)
            throw RpcError{protocol::Failed, K("NFC is off")};
        const QString uri = params.value(K("uri")).toString().trimmed();
        const QString text = params.value(K("text")).toString();
        if (uri.isEmpty() && text.isEmpty())
            throw RpcError{protocol::InvalidParams, K("uri or text")};
        const QByteArray message = !uri.isEmpty()
            ? nfc::uriMessage(uri)
            : nfc::textMessage(text, m_settings->value(K("system.language")).toString().left(2));
        QMetaObject::invokeMethod(m_adapter, "setPendingWrite", Qt::QueuedConnection, Q_ARG(QByteArray, message));
        m_write = QJsonObject{{K("waiting"), true}, {K("bytes"), int(message.size())}};
        m_writeTimeout.start();
        changed();
        return state();
    }
    if (call == QLatin1String("cancelWrite")) {
        QMetaObject::invokeMethod(m_adapter, "setPendingWrite", Qt::QueuedConnection, Q_ARG(QByteArray, QByteArray()));
        m_writeTimeout.stop();
        m_write = QJsonObject();
        changed();
        return state();
    }
    if (call == QLatin1String("forget")) {
        m_tag = QJsonObject();
        changed();
        return state();
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
