// SPDX-License-Identifier: Apache-2.0
#include "cloudyservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QNetworkReply>
#include <QTcpSocket>

#include <unistd.h>

Q_LOGGING_CATEGORY(lcCloudy, "astrad.cloudy")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }
constexpr quint16 kPort = 8742;
}

// Small instruction models that run well on a phone CPU (Apache 2.0).
const QList<CloudyService::Model> &CloudyService::models()
{
    static const QList<Model> list{
        {K("light"), K("Cloudy Light"), K("qwen2.5-0.5b-instruct-q4_k_m.gguf"),
         K("https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf"), 491400032},
        {K("standard"), K("Cloudy"), K("qwen2.5-1.5b-instruct-q4_k_m.gguf"),
         K("https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"), 1117320736},
    };
    return list;
}

CloudyService::CloudyService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_dir(Paths::resolve(QStringLiteral("/data/cloudy")))
{
    QDir().mkpath(m_dir);
    m_idle.setSingleShot(true);
    m_idle.setInterval(10 * 60 * 1000);
    connect(&m_idle, &QTimer::timeout, this, &CloudyService::stop);
    // Until llama-server answers on its port, Cloudy shows "starting".
    m_health.setInterval(500);
    connect(&m_health, &QTimer::timeout, this, [this] {
        auto *socket = new QTcpSocket(this);
        connect(socket, &QTcpSocket::connected, this, [this, socket] {
            socket->deleteLater();
            m_health.stop();
            m_ready = true;
            announce();
        });
        connect(socket, &QTcpSocket::errorOccurred, socket, &QObject::deleteLater);
        socket->connectToHost(QStringLiteral("127.0.0.1"), kPort);
    });
    m_announce.setSingleShot(true);
    m_announce.setInterval(400);
    connect(&m_announce, &QTimer::timeout, this, [this] {
        m_server->broadcast(K("cloudy.changed"), state());
    });
}

CloudyService::~CloudyService()
{
    stop();
}

const CloudyService::Model *CloudyService::model(const QString &id) const
{
    for (const Model &m : models())
        if (m.id == id)
            return &m;
    return nullptr;
}

QString CloudyService::pathOf(const Model &m) const
{
    return m_dir + QLatin1Char('/') + m.file;
}

QJsonObject CloudyService::state() const
{
    QJsonArray list;
    for (const Model &m : models())
        list.append(QJsonObject{{K("id"), m.id}, {K("name"), m.name}, {K("size"), double(m.size)},
                                {K("installed"), QFileInfo::exists(pathOf(m))}});
    return {{K("models"), list},
            {K("engine"), QFileInfo::exists(Paths::resolve(QStringLiteral("/system/bin/llama-server")))},
            {K("downloading"), m_downloading},
            {K("progress"), m_total > 0 ? double(m_received) / double(m_total) : 0.0},
            {K("running"), m_running},
            {K("ready"), m_ready},
            {K("port"), kPort},
            {K("error"), m_error}};
}

void CloudyService::announce()
{
    if (!m_announce.isActive())
        m_announce.start();
}

void CloudyService::download(const Model &m)
{
    if (m_reply)
        return;
    m_error.clear();
    m_downloading = m.id;
    m_received = 0;
    m_total = m.size;
    m_part.setFileName(pathOf(m) + QStringLiteral(".part"));
    if (!m_part.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        m_error = m_part.errorString();
        m_downloading.clear();
        announce();
        return;
    }
    QNetworkRequest req{QUrl(m.url)};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, K("astraOS-Cloudy/1.0"));
    QNetworkReply *reply = m_network.get(req);
    m_reply = reply;
    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 got, qint64 total) {
        m_received = got;
        if (total > 0)
            m_total = total;
        announce();
    });
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] { m_part.write(reply->readAll()); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, m] {
        reply->deleteLater();
        m_part.write(reply->readAll());
        m_part.close();
        const bool ok = reply->error() == QNetworkReply::NoError && m_part.size() > 1024 * 1024;
        if (ok) {
            QFile::remove(pathOf(m));
            m_part.rename(pathOf(m));
            qCInfo(lcCloudy) << "downloaded" << m.file;
        } else {
            if (reply->error() != QNetworkReply::OperationCanceledError)
                m_error = reply->errorString();
            m_part.remove();
        }
        m_downloading.clear();
        announce();
    });
    announce();
}

void CloudyService::start(const Model &m)
{
    m_idle.start();
    if (m_process && m_running == m.id)
        return;
    stop();
    const QString engine = Paths::resolve(QStringLiteral("/system/bin/llama-server"));
    if (!QFileInfo::exists(engine))
        throw RpcError{protocol::Failed, K("The Cloudy engine is not part of this system")};
    if (!QFileInfo::exists(pathOf(m)))
        throw RpcError{protocol::Failed, K("Download the model first")};
    m_process = new QProcess(this);
    m_process->setProgram(engine);
    const int threads = qBound(2, int(sysconf(_SC_NPROCESSORS_ONLN)) - 2, 6);
    m_process->setArguments({K("--model"), pathOf(m), K("--host"), K("127.0.0.1"), K("--port"), QString::number(kPort),
                             K("--ctx-size"), K("4096"), K("--threads"), QString::number(threads), K("--jinja"),
                             K("--no-webui")});
    m_process->setProcessChannelMode(QProcess::ForwardedErrorChannel);
    if (!Paths::isDevelopmentRoot() && getuid() == 0)
        m_process->setChildProcessModifier([] {
            if (setgid(1000) != 0 || setuid(1000) != 0)   // the system user, not root
                _exit(126);
        });
    QProcess *process = m_process;
    connect(process, &QProcess::finished, this, [this, process](int code) {
        if (m_process == process) {
            qCInfo(lcCloudy) << "llama-server exited" << code;
            m_process = nullptr;
            m_running.clear();
            m_ready = false;
            announce();
        }
        process->deleteLater();
    });
    m_process->start();
    m_running = m.id;
    m_ready = false;
    m_health.start();
    announce();
}

void CloudyService::stop()
{
    m_health.stop();
    m_idle.stop();
    if (m_process) {
        QProcess *p = std::exchange(m_process, nullptr);
        p->terminate();
        if (!p->waitForFinished(2000))
            p->kill();
        p->deleteLater();
    }
    m_running.clear();
    m_ready = false;
    announce();
}

QJsonValue CloudyService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    if (!caller.isSystem() && caller.package != QLatin1String("com.astra.aispace"))
        throw RpcError{protocol::PermissionDenied, K("only Cloudy uses the on-device model")};
    const Model *m = model(params.value(K("model")).toString(QStringLiteral("light")));
    if (call == QLatin1String("state"))
        return state();
    if (call == QLatin1String("download")) {
        if (!m) throw RpcError{protocol::InvalidParams, K("unknown model")};
        download(*m);
        return state();
    }
    if (call == QLatin1String("cancel")) {
        if (m_reply) m_reply->abort();
        return true;
    }
    if (call == QLatin1String("remove")) {
        if (!m) throw RpcError{protocol::InvalidParams, K("unknown model")};
        if (m_running == m->id) stop();
        QFile::remove(pathOf(*m));
        announce();
        return true;
    }
    if (call == QLatin1String("start")) {
        if (!m) throw RpcError{protocol::InvalidParams, K("unknown model")};
        start(*m);
        return state();
    }
    if (call == QLatin1String("keepAlive")) {
        if (m_process) m_idle.start();
        return true;
    }
    if (call == QLatin1String("stop")) {
        stop();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
