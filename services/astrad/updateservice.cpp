// SPDX-License-Identifier: Apache-2.0
#include "updateservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
QString otaDir()
{
    return Paths::resolve(QStringLiteral("/data/ota"));
}
} // namespace

UpdateService::UpdateService(Server *server, SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_network(new QNetworkAccessManager(this))
{
}

QJsonObject UpdateService::info() const
{
    return {
        {K("version"), Properties::get(K("ro.astra.version"))},
        {K("codename"), Properties::get(K("ro.astra.codename"))},
        {K("channel"), Properties::get(K("ro.astra.channel"))},
        {K("build"), Properties::getInt(K("ro.astra.build.number"), 0)},
        {K("buildId"), Properties::get(K("ro.astra.build.id"))},
        {K("buildDate"), Properties::get(K("ro.astra.build.date")).toDouble()},
        {K("commit"), Properties::get(K("ro.astra.build.commit"))},
        {K("device"), Properties::get(K("ro.product.device"), K("generic"))},
        {K("lastCheck"), m_settings->value(K("update.last_check"))},
        {K("status"), m_status},
        {K("error"), m_error},
        {K("available"), m_available},     // the published manifest: version, codename, build, url, sha256, size, notes
        {K("progress"), m_progress},
    };
}

void UpdateService::setStatus(const QString &status, const QString &error)
{
    m_status = status;
    m_error = error;
    m_server->broadcast(K("update.changed"), info());
}

void UpdateService::check()
{
    const QString base = Properties::get(K("ro.astra.ota.url"));
    const QString device = Properties::get(K("ro.product.device"), K("generic"));
    const QString channel = Properties::get(K("ro.astra.channel"), K("delta"));
    if (base.isEmpty()) {
        setStatus(K("error"), K("No update server is configured for this build"));
        return;
    }
    setStatus(K("checking"));
    QNetworkRequest request(QUrl(QStringLiteral("%1/%2/%3.json").arg(base, device, channel)));
    request.setTransferTimeout(20000);
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        m_settings->setValue(K("update.last_check"), double(QDateTime::currentMSecsSinceEpoch()));
        if (reply->error() == QNetworkReply::ContentNotFoundError) {
            m_available = {};
            setStatus(K("uptodate")); // nothing published for this device/channel yet
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            setStatus(K("error"), reply->errorString());
            return;
        }
        const QJsonObject manifest = QJsonDocument::fromJson(reply->readAll()).object();
        const int ours = Properties::getInt(K("ro.astra.build.number"), 0);
        if (manifest.value(K("build")).toInt() > ours && !manifest.value(K("url")).toString().isEmpty()) {
            m_available = manifest;
            setStatus(K("available"));
        } else {
            m_available = {};
            setStatus(K("uptodate"));
        }
    });
}

void UpdateService::download()
{
    if (m_available.isEmpty() || m_download)
        return;
    QDir().mkpath(otaDir());
    const QString target = otaDir() + QStringLiteral("/update-%1.zip").arg(m_available.value(K("build")).toInt());
    auto *file = new QFile(target + QStringLiteral(".part"), this);
    if (!file->open(QIODevice::WriteOnly)) {
        setStatus(K("error"), file->errorString());
        delete file;
        return;
    }
    m_progress = 0;
    setStatus(K("downloading"));
    m_download = m_network->get(QNetworkRequest(QUrl(m_available.value(K("url")).toString())));
    connect(m_download, &QNetworkReply::readyRead, this, [this, file] { file->write(m_download->readAll()); });
    connect(m_download, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        m_progress = total > 0 ? double(got) / double(total) : 0;
        m_server->broadcast(K("update.changed"), info());
    });
    connect(m_download, &QNetworkReply::finished, this, [this, file, target] {
        file->write(m_download->readAll());
        file->close();
        const bool ok = m_download->error() == QNetworkReply::NoError;
        const QString error = m_download->errorString();
        m_download->deleteLater();
        m_download = nullptr;
        if (!ok) {
            file->remove();
            file->deleteLater();
            setStatus(K("error"), error);
            return;
        }
        // Verify before announcing the package as ready.
        QFile check(file->fileName());
        QCryptographicHash hash(QCryptographicHash::Sha256);
        if (check.open(QIODevice::ReadOnly))
            hash.addData(&check);
        check.close();
        const QString expected = m_available.value(K("sha256")).toString().toLower();
        if (!expected.isEmpty() && QString::fromLatin1(hash.result().toHex()) != expected) {
            file->remove();
            file->deleteLater();
            setStatus(K("error"), K("The downloaded update is corrupted"));
            return;
        }
        QFile::remove(target);
        file->rename(target);
        file->deleteLater();
        m_available.insert(K("file"), target);
        setStatus(K("ready"));
    });
}

QJsonValue UpdateService::handle(const QString &call, const QJsonObject &, const Caller &caller)
{
    if (call == QLatin1String("info"))
        return info();
    caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
    if (call == QLatin1String("check")) {
        check();
        return true;
    }
    if (call == QLatin1String("download")) {
        download();
        return true;
    }
    if (call == QLatin1String("cancel")) {
        if (m_download)
            m_download->abort();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
