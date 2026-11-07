// SPDX-License-Identifier: Apache-2.0
#include "updateservice.h"
#include "initcontrol.h"
#include "notificationservice.h"
#include "permissions.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/properties.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QStorageInfo>
#include <QTimer>

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
QString downloadDir()
{
    return otaDir() + QStringLiteral("/download");
}
QString applyDir()
{
    return otaDir() + QStringLiteral("/apply");
}
// What each downloaded file becomes in /data/ota/apply (core/init/ota.h).
QString unpackedName(const QString &file)
{
    return file == QLatin1String("super") ? QStringLiteral("super.img") : QStringLiteral("esp.fat");
}
QNetworkRequest githubRequest(const QUrl &url, const char *accept)
{
    QNetworkRequest request(url);
    request.setRawHeader("Accept", accept);
    request.setRawHeader("User-Agent", "astraOS-update");
    request.setTransferTimeout(30000);
    return request;
}
constexpr int kCheckIntervalMs = 12 * 3600 * 1000;
} // namespace

UpdateService::UpdateService(Server *server, SettingsService *settings, NotificationService *notifications,
                             QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_notifications(notifications)
    , m_network(new QNetworkAccessManager(this))
    , m_timer(new QTimer(this))
{
    // GitHub's download links redirect to its file storage.
    m_network->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
    QTimer::singleShot(0, this, &UpdateService::afterUpdate);
    // Automatic checks: a minute after the start (the network comes up), then twice a day.
    m_timer->setInterval(kCheckIntervalMs);
    connect(m_timer, &QTimer::timeout, this, [this] { check(true); });
    m_timer->start();
    QTimer::singleShot(60 * 1000, this, [this] { check(true); });
}

QJsonObject UpdateService::release() const
{
    QFile file(Paths::resolve(QStringLiteral("/vendor/etc/astra-release.json")));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

// "owner/name", from ro.astra.ota.repo (which may also be a github.com address).
QString UpdateService::repository() const
{
    QString repo = Properties::get(K("ro.astra.ota.repo")).trimmed();
    for (const char *prefix : {"https://github.com/", "http://github.com/", "github.com/"}) {
        if (repo.startsWith(QLatin1String(prefix)))
            repo = repo.mid(int(qstrlen(prefix)));
    }
    if (repo.endsWith(QLatin1String(".git")))
        repo.chop(4);
    while (repo.endsWith(QLatin1Char('/')))
        repo.chop(1);
    return repo.count(QLatin1Char('/')) == 1 ? repo : QString();
}

// The channel the phone follows: the user's choice, else its build's.
QString UpdateService::channel() const
{
    const QString chosen = m_settings->value(K("update.channel")).toString();
    if (chosen == QLatin1String("stable") || chosen == QLatin1String("prerelease"))
        return chosen;
    return Properties::get(K("ro.astra.ota.channel")) == QLatin1String("prerelease") ? K("prerelease") : K("stable");
}

QJsonObject UpdateService::info() const
{
    return {
        {K("version"), Properties::get(K("ro.astra.version"))},
        {K("codename"), Properties::get(K("ro.astra.codename"))},
        {K("channel"), channel()},
        {K("buildChannel"), Properties::get(K("ro.astra.ota.channel"), K("local"))},
        {K("tag"), Properties::get(K("ro.astra.ota.tag"))},
        {K("time"), double(Properties::getInt(K("ro.astra.ota.time"), 0))},
        {K("repository"), repository()},
        {K("build"), Properties::getInt(K("ro.astra.build.number"), 0)},
        {K("buildId"), Properties::get(K("ro.astra.build.id"))},
        {K("buildDate"), Properties::get(K("ro.astra.build.date")).toDouble()},
        {K("commit"), Properties::get(K("ro.astra.build.commit"))},
        {K("device"), Properties::get(K("ro.product.device"), K("generic"))},
        {K("lastCheck"), m_settings->value(K("update.last_check"))},
        {K("status"), m_status},
        {K("error"), m_error},
        {K("available"), m_available},
        {K("progress"), m_progress},
    };
}

void UpdateService::setStatus(const QString &status, const QString &error)
{
    m_status = status;
    m_error = error;
    m_server->broadcast(K("update.changed"), info());
}

void UpdateService::fail(const QString &error)
{
    qWarning("update: %s", qPrintable(error));
    setStatus(K("error"), error);
}

// Lists the device repository's releases and takes the newest of the channel
// that has an ota.json.
void UpdateService::check(bool automatic)
{
    if (m_status == QLatin1String("checking") || m_status == QLatin1String("downloading") ||
        m_status == QLatin1String("preparing") || m_status == QLatin1String("ready") ||
        m_status == QLatin1String("installing"))
        return;
    if (automatic && !m_settings->value(K("update.auto_check")).toBool(true))
        return;
    const QString repo = repository();
    if (repo.isEmpty()) {
        if (!automatic)
            fail(K("This build names no repository to update from (ro.astra.ota.repo)"));
        return;
    }
    setStatus(K("checking"));
    const QUrl url(QStringLiteral("https://api.github.com/repos/%1/releases?per_page=30").arg(repo));
    QNetworkReply *reply = m_network->get(githubRequest(url, "application/vnd.github+json"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, automatic] {
        reply->deleteLater();
        m_settings->setValue(K("update.last_check"), double(QDateTime::currentMSecsSinceEpoch()));
        if (reply->error() != QNetworkReply::NoError) {
            if (automatic)
                setStatus(K("idle")); // offline: try again later, quietly
            else
                fail(reply->error() == QNetworkReply::ContentNotFoundError
                         ? K("The update repository %1 was not found").arg(repository())
                         : reply->errorString());
            return;
        }
        const bool prerelease = channel() == QLatin1String("prerelease");
        for (const QJsonValue &v : QJsonDocument::fromJson(reply->readAll()).array()) {
            const QJsonObject rel = v.toObject();
            if (rel.value(K("draft")).toBool() || (!prerelease && rel.value(K("prerelease")).toBool()))
                continue;
            for (const QJsonValue &a : rel.value(K("assets")).toArray()) {
                if (a.toObject().value(K("name")).toString() == QLatin1String("ota.json")) {
                    checkManifest(rel, automatic);
                    return;
                }
            }
        }
        m_available = {};
        setStatus(K("uptodate"));
    });
}

void UpdateService::checkManifest(const QJsonObject &rel, bool automatic)
{
    QHash<QString, QString> urls;
    for (const QJsonValue &a : rel.value(K("assets")).toArray()) {
        const QJsonObject asset = a.toObject();
        urls.insert(asset.value(K("name")).toString(), asset.value(K("browser_download_url")).toString());
    }
    QNetworkReply *reply = m_network->get(githubRequest(QUrl(urls.value(K("ota.json"))), "application/octet-stream"));
    connect(reply, &QNetworkReply::finished, this, [this, reply, rel, urls, automatic] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            if (automatic)
                setStatus(K("idle"));
            else
                fail(reply->errorString());
            return;
        }
        QJsonObject m = QJsonDocument::fromJson(reply->readAll()).object();
        const QString device = Properties::get(K("ro.product.device"), K("generic"));
        const qint64 ours = Properties::getInt(K("ro.astra.ota.time"), 0);
        const QJsonObject files = m.value(K("files")).toObject();
        const bool complete = urls.contains(files.value(K("super")).toObject().value(K("name")).toString()) &&
                              urls.contains(files.value(K("esp")).toObject().value(K("name")).toString());
        if (m.value(K("device")).toString() != device || qint64(m.value(K("time")).toDouble()) <= ours ||
            m.value(K("tag")).toString() == Properties::get(K("ro.astra.ota.tag")) || !complete) {
            m_available = {};
            setStatus(K("uptodate"));
            return;
        }
        qint64 size = 0;
        QJsonObject withUrls;
        for (const QString &key : {K("super"), K("esp")}) {
            QJsonObject f = files.value(key).toObject();
            f.insert(K("url"), urls.value(f.value(K("name")).toString()));
            size += qint64(f.value(K("size")).toDouble());
            withUrls.insert(key, f);
        }
        m.insert(K("files"), withUrls);
        m.insert(K("size"), double(size));
        m.insert(K("prerelease"), rel.value(K("prerelease")).toBool());
        m.insert(K("page"), rel.value(K("html_url")).toString());
        const bool announce = m_settings->value(K("update.announced")).toString() != m.value(K("tag")).toString();
        m_available = m;
        setStatus(K("available"));
        if (announce) {
            m_settings->setValue(K("update.announced"), m.value(K("tag")));
            announceAvailable();
        }
    });
}

void UpdateService::announceAvailable()
{
    if (!m_notifications)
        return;
    const bool it = m_settings->value(K("system.language")).toString().startsWith(QLatin1String("it"));
    const QString version = m_available.value(K("version")).toString();
    m_notifications->post(K("com.astra.settings"),
                          it ? K("Aggiornamento disponibile") : K("Update available"),
                          (it ? K("astraOS %1 è pronto da scaricare.") : K("astraOS %1 is ready to download.")).arg(version),
                          QJsonObject{{K("args"), QJsonObject{{K("page"), K("update")}}}});
}

void UpdateService::download()
{
    if (m_available.isEmpty() || m_reply || m_status == QLatin1String("preparing"))
        return;
    const QJsonObject files = m_available.value(K("files")).toObject();
    m_total = 0;
    qint64 needed = 256ll << 20;
    for (const QString &key : {K("super"), K("esp")}) {
        const QJsonObject f = files.value(key).toObject();
        m_total += qint64(f.value(K("size")).toDouble());
        needed += qint64(f.value(K("size")).toDouble()) + qint64(f.value(K("raw_size")).toDouble());
    }
    QDir(otaDir()).removeRecursively();
    QDir().mkpath(downloadDir());
    QDir().mkpath(applyDir());
    const QStorageInfo storage(otaDir());
    if (storage.isValid() && storage.bytesAvailable() < needed) {
        fail(K("Not enough free space: the update needs %1 MB").arg(needed >> 20));
        return;
    }
    m_queue = {K("super"), K("esp")};
    m_done = 0;
    m_progress = 0;
    setStatus(K("downloading"));
    downloadNext();
}

void UpdateService::downloadNext()
{
    if (m_queue.isEmpty()) {
        prepare();
        return;
    }
    const QJsonObject f = m_available.value(K("files")).toObject().value(m_queue.first()).toObject();
    m_file = new QFile(downloadDir() + QLatin1Char('/') + f.value(K("name")).toString(), this);
    if (!m_file->open(QIODevice::WriteOnly)) {
        const QString error = m_file->errorString();
        delete m_file;
        m_file = nullptr;
        fail(error);
        return;
    }
    m_hash.reset();
    QNetworkRequest request = githubRequest(QUrl(f.value(K("url")).toString()), "application/octet-stream");
    request.setTransferTimeout(120000);
    m_reply = m_network->get(request);
    connect(m_reply, &QNetworkReply::readyRead, this, [this] {
        const QByteArray data = m_reply->readAll();
        m_hash.addData(data);
        m_file->write(data);
    });
    connect(m_reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64) {
        const double progress = m_total > 0 ? double(m_done + got) / double(m_total) : 0;
        if (progress - m_progress >= 0.005 || progress >= 1) {
            m_progress = progress;
            m_server->broadcast(K("update.changed"), info());
        }
    });
    connect(m_reply, &QNetworkReply::finished, this, [this, f] {
        const QByteArray rest = m_reply->readAll();
        m_hash.addData(rest);
        m_file->write(rest);
        m_file->close();
        const bool ok = m_reply->error() == QNetworkReply::NoError;
        const bool cancelled = m_reply->error() == QNetworkReply::OperationCanceledError;
        const QString error = m_reply->errorString();
        m_reply->deleteLater();
        m_reply = nullptr;
        m_file->deleteLater();
        m_file = nullptr;
        if (cancelled) {
            QDir(otaDir()).removeRecursively();
            m_progress = 0;
            setStatus(K("available"));
            return;
        }
        if (!ok) {
            QDir(otaDir()).removeRecursively();
            fail(error);
            return;
        }
        if (QString::fromLatin1(m_hash.result().toHex()) != f.value(K("sha256")).toString().toLower()) {
            QDir(otaDir()).removeRecursively();
            fail(K("The downloaded update is damaged: try again"));
            return;
        }
        m_done += qint64(f.value(K("size")).toDouble());
        m_queue.removeFirst();
        downloadNext();
    });
}

// Unpacks each file into /data/ota/apply and checks what the first stage will write.
void UpdateService::prepare()
{
    m_queue = {K("super"), K("esp")};
    m_progress = 1;
    setStatus(K("preparing"));
    unpackNext();
}

void UpdateService::unpackNext()
{
    if (m_queue.isEmpty()) {
        QDir(downloadDir()).removeRecursively();
        QFile manifest(applyDir() + QStringLiteral("/ota.json"));
        if (manifest.open(QIODevice::WriteOnly))
            manifest.write(QJsonDocument(m_available).toJson());
        setStatus(K("ready"));
        return;
    }
    const QString key = m_queue.first();
    const QJsonObject f = m_available.value(K("files")).toObject().value(key).toObject();
    const QString packed = downloadDir() + QLatin1Char('/') + f.value(K("name")).toString();
    const QString target = applyDir() + QLatin1Char('/') + unpackedName(key);
    // gzip and sha256sum run outside astrad: a gigabyte would hold it for seconds.
    auto *gzip = new QProcess(this);
    gzip->setStandardOutputFile(target);
    connect(gzip, &QProcess::finished, this, [this, gzip, key, f, packed, target](int code, QProcess::ExitStatus st) {
        gzip->deleteLater();
        if (st != QProcess::NormalExit || code != 0) {
            QDir(otaDir()).removeRecursively();
            fail(K("The update could not be unpacked"));
            return;
        }
        QFile::remove(packed);
        auto *sum = new QProcess(this);
        connect(sum, &QProcess::finished, this, [this, sum, f, target](int, QProcess::ExitStatus) {
            sum->deleteLater();
            const QString got = QString::fromLatin1(sum->readAllStandardOutput()).section(QLatin1Char(' '), 0, 0);
            if (got != f.value(K("raw_sha256")).toString().toLower() ||
                QFile(target).size() != qint64(f.value(K("raw_size")).toDouble())) {
                QDir(otaDir()).removeRecursively();
                fail(K("The unpacked update does not match: try again"));
                return;
            }
            m_queue.removeFirst();
            unpackNext();
        });
        sum->start(K("sha256sum"), {target});
    });
    connect(gzip, &QProcess::errorOccurred, this, [this, gzip](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart)
            return;
        gzip->deleteLater();
        QDir(otaDir()).removeRecursively();
        fail(K("The update could not be unpacked (gzip is missing)"));
    });
    gzip->start(K("gzip"), {K("-dc"), packed});
}

void UpdateService::install()
{
    if (m_status != QLatin1String("ready"))
        return;
    QFile state(applyDir() + QStringLiteral("/state"));
    if (!state.open(QIODevice::WriteOnly) || state.write("ready") != 5) {
        fail(state.errorString());
        return;
    }
    state.close();
    setStatus(K("installing"));
    // Let the event reach SysBoard (it shows that the phone restarts) first.
    QTimer::singleShot(1500, this, [this] {
        if (!sendToInit("reboot"))
            fail(K("init is not reachable: restart the phone to install"));
    });
}

void UpdateService::cancel()
{
    if (m_reply) {
        m_reply->abort(); // finished() cleans up
        return;
    }
    if (m_status == QLatin1String("ready")) {
        QDir(otaDir()).removeRecursively();
        m_progress = 0;
        setStatus(m_available.isEmpty() ? K("idle") : K("available"));
    }
}

// After a start: what the first stage did with a staged update, and the
// "what's new" notification once per installed build (it opens Tips).
void UpdateService::afterUpdate()
{
    QFile state(applyDir() + QStringLiteral("/state"));
    if (state.open(QIODevice::ReadOnly)) {
        const QByteArray s = state.readAll().trimmed();
        state.close();
        if (s == "installed") {
            QDir(otaDir()).removeRecursively();
        } else if (s == "failed") {
            QDir(otaDir()).removeRecursively();
            setStatus(K("error"), K("The update could not be installed. Your phone kept the previous version."));
        } else if (s.startsWith("applying")) {
            // The first stage could not write everything, yet the system started.
            QDir(otaDir()).removeRecursively();
            setStatus(K("error"), K("The update was only partly installed: download it again."));
        } else if (s == "ready") {
            // The phone restarted without writing it (it did not start through U-Boot):
            // it stays ready, to install with the next restart.
            QFile manifest(applyDir() + QStringLiteral("/ota.json"));
            if (manifest.open(QIODevice::ReadOnly)) {
                m_available = QJsonDocument::fromJson(manifest.readAll()).object();
                m_status = K("ready");
                state.remove();
            }
        }
    }

    const QJsonObject rel = release();
    const QString key = Properties::get(K("ro.astra.version")) + QLatin1Char('/') +
                        QString::number(Properties::getInt(K("ro.astra.ota.time"), 0));
    if (m_settings->value(K("update.seen")).toString() == key)
        return;
    m_settings->setValue(K("update.seen"), key);
    if (!m_notifications)
        return;
    const bool it = m_settings->value(K("system.language")).toString().startsWith(QLatin1String("it"));
    const QString name = QStringLiteral("astraOS %1 “%2”").arg(Properties::get(K("ro.astra.version")),
                                                               Properties::get(K("ro.astra.codename")));
    const int changes = rel.value(K("notes")).toArray().size();
    QString body = it ? K("Scopri le novità di questa versione.") : K("See what's new in this version.");
    if (changes > 0)
        body = (it ? K("%1 novità: tocca per leggerle.") : K("%1 changes: tap to read them.")).arg(changes);
    m_notifications->post(K("com.astra.tips"), name, body,
                          QJsonObject{{K("args"), QJsonObject{{K("page"), K("changelog")}}}});
}

QJsonValue UpdateService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (call == QLatin1String("info"))
        return info();
    if (call == QLatin1String("changelog")) {
        QJsonObject rel = release();
        rel.insert(K("version"), Properties::get(K("ro.astra.version")));
        rel.insert(K("codename"), Properties::get(K("ro.astra.codename")));
        return rel;
    }
    caller.require(QLatin1String(permissions::MANAGE_SETTINGS));
    if (call == QLatin1String("check")) {
        check();
        return true;
    }
    if (call == QLatin1String("download")) {
        download();
        return true;
    }
    if (call == QLatin1String("install")) {
        install();
        return true;
    }
    if (call == QLatin1String("cancel")) {
        cancel();
        return true;
    }
    if (call == QLatin1String("setChannel")) {
        const QString c = params.value(K("channel")).toString();
        if (c != QLatin1String("stable") && c != QLatin1String("prerelease"))
            throw RpcError{protocol::InvalidParams, K("channel must be stable or prerelease")};
        m_settings->setValue(K("update.channel"), c);
        m_available = {};
        setStatus(K("idle"));
        check();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
