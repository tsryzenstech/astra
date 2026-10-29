// SPDX-License-Identifier: Apache-2.0
#include "locationservice.h"
#include "network/backends.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/protocol.h>

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QNetworkReply>

Q_LOGGING_CATEGORY(lcLocation, "astrad.location")

namespace astrad {

using namespace astra;

namespace {
const QString kBeaconDb = QStringLiteral("https://api.beacondb.net/v1/geolocate");
QString K(const char *s) { return QString::fromLatin1(s); }
} // namespace

LocationService::LocationService(Server *server, SettingsService *settings, network::WifiBackend *wifi,
                                 network::CellularBackend *cell, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_wifi(wifi)
    , m_cell(cell)
{
    // While an app follows the location (Maps), refresh every 10 seconds.
    m_watch.setInterval(10000);
    connect(&m_watch, &QTimer::timeout, this, [this] {
        if (QDateTime::currentMSecsSinceEpoch() > m_watchUntil || !enabled())
            m_watch.stop();
        else
            refresh();
    });
}

bool LocationService::enabled() const
{
    const QJsonValue v = m_settings->value(K("controls.location"));
    return v.isUndefined() || v.isNull() || v.toBool();
}

void LocationService::locate(std::function<void(const QJsonObject &)> done)
{
    if (!enabled()) {
        done({});
        return;
    }
    m_waiting.append(std::move(done));
    refresh();
}

void LocationService::refresh()
{
    if (m_busy)
        return;
    m_busy = true;
    if (m_cell && m_cell->available())
        m_cell->locate([this](const QJsonObject &modem) { lookup(modem); });
    else
        lookup({});
}

void LocationService::lookup(const QJsonObject &modem)
{
    const QJsonObject gnss = modem.value(K("gnss")).toObject();
    if (!gnss.isEmpty()) {
        QJsonObject fix = gnss;
        fix.insert(K("source"), K("gnss"));
        finish(fix);
        return;
    }
    QJsonObject body{{K("considerIp"), true}};
    const QJsonArray aps = m_wifi ? m_wifi->accessPoints() : QJsonArray();
    if (aps.size() >= 2) // a single access point is not enough to place anyone
        body.insert(K("wifiAccessPoints"), aps);
    if (modem.contains(K("cell")))
        body.insert(K("cellTowers"), QJsonArray{modem.value(K("cell"))});
    const QString source = aps.size() >= 2 ? K("wifi") : modem.contains(K("cell")) ? K("cell") : K("ip");

    QNetworkRequest req{QUrl(kBeaconDb)};
    req.setHeader(QNetworkRequest::ContentTypeHeader, K("application/json"));
    req.setHeader(QNetworkRequest::UserAgentHeader, K("astraOS-location/1.0 (+https://github.com/tsryzenstech/astra)"));
    req.setTransferTimeout(15000);
    QNetworkReply *reply = m_network.post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, source] {
        reply->deleteLater();
        const QJsonObject r = QJsonDocument::fromJson(reply->readAll()).object();
        const QJsonObject l = r.value(K("location")).toObject();
        if (reply->error() != QNetworkReply::NoError || l.isEmpty()) {
            qCInfo(lcLocation) << "no network fix:" << reply->errorString();
            finish({});
            return;
        }
        finish({{K("lat"), l.value(K("lat")).toDouble()}, {K("lon"), l.value(K("lng")).toDouble()},
                {K("accuracy"), r.value(K("accuracy")).toDouble()}, {K("source"), source}});
    });
}

void LocationService::finish(const QJsonObject &result)
{
    m_busy = false;
    if (!result.isEmpty()) {
        m_fix = result;
        m_fix.insert(K("time"), double(QDateTime::currentMSecsSinceEpoch()));
        m_server->broadcast(K("location.changed"), m_fix,
                            [](const Caller &c) { return c.can(QLatin1String(permissions::LOCATION)); });
    }
    const auto waiting = std::exchange(m_waiting, {});
    for (const auto &w : waiting)
        w(result.isEmpty() ? QJsonObject() : m_fix);
}

QJsonValue LocationService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::LOCATION));
    if (call == QLatin1String("state"))
        return QJsonObject{{K("enabled"), enabled()}, {K("fix"), m_fix}};
    if (call == QLatin1String("get")) {
        if (!enabled())
            throw RpcError{protocol::Failed, K("Location Services are off")};
        const double maxAge = params.value(K("maxAge")).toDouble(60) * 1000;
        if (params.value(K("watch")).toBool()) {
            m_watchUntil = QDateTime::currentMSecsSinceEpoch() + 60000;
            if (!m_watch.isActive())
                m_watch.start();
        }
        if (!m_fix.isEmpty() && QDateTime::currentMSecsSinceEpoch() - m_fix.value(K("time")).toDouble() < maxAge)
            return m_fix;
        const PendingReply reply = caller.defer();
        locate([reply](const QJsonObject &fix) {
            if (fix.isEmpty())
                reply.reject(protocol::Failed, K("The location is not available right now"));
            else
                reply.resolve(fix);
        });
        return Deferred;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
