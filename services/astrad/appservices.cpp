// SPDX-License-Identifier: Apache-2.0
#include "appservices.h"
#include "packagemanager.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QProcess>
#include <QTimer>

#include <grp.h>
#include <unistd.h>

Q_LOGGING_CATEGORY(lcSvc, "astrad.services")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}
bool mayHaveServices(const QString &package)
{
    return package.startsWith(QLatin1String("com.astra."));
}
constexpr int kFirstRetryMs = 2000;
constexpr int kMaxRetryMs = 5 * 60 * 1000;
} // namespace

AppServices::AppServices(Server *server, PackageManager *packages, SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_packages(packages)
    , m_settings(settings)
{
    connect(packages, &PackageManager::packageInstalled, this, [this](const QString &pkg) {
        stopPackage(pkg); // the new version's program, the new declaration
        sync(pkg);
    });
    connect(packages, &PackageManager::packageRemoved, this, &AppServices::stopPackage);
    connect(packages, &PackageManager::dataCleared, this, [this](const QString &pkg) {
        stopPackage(pkg);
        QTimer::singleShot(1000, this, [this, pkg] { sync(pkg); });
    });
    // Permissions decide the groups a service starts with: start it again.
    connect(packages, &PackageManager::permissionsChanged, this, [this](const QString &pkg, bool groupsChanged) {
        if (!groupsChanged)
            return;
        stopPackage(pkg);
        sync(pkg);
    });
}

AppServices::~AppServices()
{
    for (Instance &i : m_instances) {
        i.stopping = true;
        if (i.process) {
            i.process->terminate();
            if (!i.process->waitForFinished(2000))
                i.process->kill();
        }
    }
}

void AppServices::startAll()
{
    for (const QString &pkg : m_packages->packages())
        sync(pkg);
}

void AppServices::sync(const QString &package)
{
    if (!m_packages->contains(package))
        return;
    const QJsonObject info = m_packages->info(package);
    const QJsonArray declared = info.value(K("services")).toArray();
    if (declared.isEmpty())
        return;
    if (!mayHaveServices(package)) {
        qCWarning(lcSvc) << package << "declares services; only astraOS's own apps may have them";
        return;
    }
    for (const QJsonValue &v : declared) {
        const QString id = v.toObject().value(K("id")).toString();
        if (id.isEmpty())
            continue;
        const QString k = key(package, id);
        if (m_instances.contains(k) && m_instances[k].process)
            continue;
        Instance &i = m_instances[k];
        i.package = package;
        i.id = id;
        i.stopping = false;
        launch(k);
    }
}

void AppServices::stopPackage(const QString &package)
{
    for (auto it = m_instances.begin(); it != m_instances.end();) {
        Instance &i = it.value();
        if (i.package != package) {
            ++it;
            continue;
        }
        i.stopping = true;
        if (i.retry)
            i.retry->stop();
        if (i.process) {
            QProcess *p = i.process;
            i.process = nullptr;
            p->disconnect(this);
            p->terminate();
            if (!p->waitForFinished(3000))
                p->kill();
            p->deleteLater();
        }
        if (i.retry)
            i.retry->deleteLater();
        it = m_instances.erase(it);
    }
}

void AppServices::launch(const QString &k)
{
    Instance &i = m_instances[k];
    const QJsonObject info = m_packages->info(i.package);
    QJsonObject decl;
    for (const QJsonValue &v : info.value(K("services")).toArray())
        if (v.toObject().value(K("id")).toString() == i.id)
            decl = v.toObject();
    const QString code = info.value(K("codePath")).toString();
    const QString exec = QDir::cleanPath(code + QLatin1Char('/') + decl.value(K("exec")).toString());
    if (decl.isEmpty() || !exec.startsWith(code + QLatin1Char('/')) || !QFileInfo(exec).isExecutable()) {
        qCWarning(lcSvc) << i.package << i.id << "has no program to run at" << exec;
        return;
    }
    const uid_t uid = uid_t(info.value(K("uid")).toInt());
    const QString home = info.value(K("dataDir")).toString();
    QDir().mkpath(home + QStringLiteral("/cache"));

    QProcessEnvironment env;
    const QString runtimeDir = Paths::resolve(QStringLiteral("/run/user/%1").arg(uid));
    QDir().mkpath(runtimeDir);
    const bool asRoot = geteuid() == 0;
    if (asRoot) {
        const QByteArray rd = QFile::encodeName(runtimeDir);
        if (chown(rd.constData(), uid, uid) != 0)
            qCWarning(lcSvc) << "cannot chown" << runtimeDir;
    }
    const QString language = m_settings->value(K("system.language")).toString(K("en"));
    env.insert(K("PATH"), K("/system/bin"));
    env.insert(K("HOME"), home);
    env.insert(K("TMPDIR"), home + QStringLiteral("/cache"));
    env.insert(K("XDG_CONFIG_HOME"), home + QStringLiteral("/files/.config"));
    env.insert(K("XDG_CACHE_HOME"), home + QStringLiteral("/cache"));
    env.insert(K("XDG_DATA_HOME"), home + QStringLiteral("/files"));
    env.insert(K("XDG_RUNTIME_DIR"), runtimeDir);
    env.insert(K("LANG"), language + QStringLiteral(".UTF-8"));
    env.insert(K("ASTRA_LANGUAGE"), language);
    env.insert(K("ASTRA_PACKAGE"), i.package);
    env.insert(K("ASTRA_SERVICE"), i.id);
    env.insert(K("ASTRA_CODE_PATH"), code);
    env.insert(K("ASTRA_SOCKET"), Paths::resolve(QStringLiteral("/dev/socket/astrad")));
    env.insert(K("SSL_CERT_FILE"), Paths::resolve(QStringLiteral("/system/etc/ssl/certs/ca-certificates.crt")));
    const QString tz = m_settings->value(K("system.timezone")).toString();
    if (!tz.isEmpty())
        env.insert(K("TZ"), tz);
    if (qEnvironmentVariableIsSet("ASTRA_ROOT"))
        env.insert(K("ASTRA_ROOT"), qEnvironmentVariable("ASTRA_ROOT"));

    QStringList args;
    for (const QJsonValue &a : decl.value(K("args")).toArray())
        args << a.toString();

    auto *process = new QProcess(this);
    process->setProgram(exec);
    process->setArguments(args);
    process->setProcessEnvironment(env);
    process->setWorkingDirectory(home);
    // Its own log, not the system's: a busy service must not flood the kernel log.
    process->setStandardOutputFile(home + QStringLiteral("/cache/") + i.id + QStringLiteral(".log"), QIODevice::Truncate);
    process->setStandardErrorFile(home + QStringLiteral("/cache/") + i.id + QStringLiteral(".log"), QIODevice::Append);
    if (asRoot) {
        const QList<gid_t> groups = m_packages->groupsOf(i.package);
        process->setChildProcessModifier([uid, groups] {
            if (setgroups(size_t(groups.size()), groups.constData()) != 0 || setgid(uid) != 0 || setuid(uid) != 0)
                _exit(126);
        });
    }
    connect(process, &QProcess::finished, this, [this, k, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (!m_instances.contains(k))
            return;
        Instance &inst = m_instances[k];
        inst.process = nullptr;
        qCInfo(lcSvc) << k << "exited" << code << (status == QProcess::CrashExit ? "(crashed)" : "");
        if (inst.stopping)
            return;
        // A service that ran a while is not failing: start again quickly.
        if (QDateTime::currentMSecsSinceEpoch() - inst.started > 60 * 1000)
            inst.failures = 0;
        scheduleRetry(k);
    });
    connect(process, &QProcess::errorOccurred, this, [this, k, process](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart || !m_instances.contains(k))
            return;
        qCWarning(lcSvc) << k << "cannot start:" << process->errorString();
        process->deleteLater();
        m_instances[k].process = nullptr;
        scheduleRetry(k);
    });
    i.process = process;
    i.started = QDateTime::currentMSecsSinceEpoch();
    process->start();
    qCInfo(lcSvc) << "started" << k << "uid" << uid;
}

void AppServices::scheduleRetry(const QString &k)
{
    Instance &i = m_instances[k];
    const int delay = qMin(kMaxRetryMs, kFirstRetryMs << qMin(i.failures, 8));
    i.failures++;
    if (!i.retry) {
        i.retry = new QTimer(this);
        i.retry->setSingleShot(true);
        connect(i.retry, &QTimer::timeout, this, [this, k] {
            if (m_instances.contains(k) && !m_instances[k].process && !m_instances[k].stopping)
                launch(k);
        });
    }
    i.retry->start(delay);
}

QJsonValue AppServices::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString pkg = params.value(K("package")).toString(caller.package);
    if (!caller.isSystem() && pkg != caller.package)
        throw RpcError{protocol::PermissionDenied, K("only the app itself or the system")};
    if (call == QLatin1String("list")) {
        QJsonArray out;
        for (const Instance &i : std::as_const(m_instances)) {
            if (!caller.isSystem() && i.package != caller.package)
                continue;
            out.append(QJsonObject{{K("package"), i.package}, {K("id"), i.id},
                                   {K("running"), i.process != nullptr},
                                   {K("pid"), i.process ? qint64(i.process->processId()) : 0},
                                   {K("restarts"), i.failures}});
        }
        return out;
    }
    if (call == QLatin1String("restart")) {
        stopPackage(pkg);
        sync(pkg);
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
