// SPDX-License-Identifier: Apache-2.0
#include "packagemanager.h"
#include "jsonstore.h"
#include "permissions.h"

#include <astra/apkg.h>
#include <astra/global.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QLoggingCategory>

#include <unistd.h>

Q_LOGGING_CATEGORY(lcPm, "astrad.packages")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s)
{
    return QString::fromLatin1(s);
}

qint64 directorySize(const QString &path)
{
    qint64 total = 0;
    QDirIterator it(path, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
    while (it.hasNext())
        total += it.nextFileInfo().size();
    return total;
}
} // namespace

PackageManager::PackageManager(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_dbPath(Paths::dataSystem() + QStringLiteral("/packages.json"))
{
    const QJsonObject db = loadJson(m_dbPath);
    for (auto it = db.begin(); it != db.end(); ++it)
        m_packages.insert(it.key(), it.value().toObject());
}

void PackageManager::scan()
{
    struct Root {
        QString dir;
        bool privileged;
    };
    const QList<Root> roots{{Paths::privilegedApps(), true}, {Paths::systemApps(), false}, {Paths::productApps(), false}};

    QSet<QString> seenSystem;
    for (const Root &root : roots) {
        QDirIterator it(root.dir, {QStringLiteral("*.apkg")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            Apkg apkg;
            if (!apkg.open(path)) {
                qCWarning(lcPm) << "skipping" << path << apkg.errorString();
                continue;
            }
            const QString pkg = apkg.manifest().value(K("package")).toString();
            seenSystem.insert(pkg);
            const QJsonObject existing = m_packages.value(pkg);
            const QString checksum = QString::fromLatin1(apkg.checksum().toHex());
            if (existing.value(K("checksum")).toString() == checksum &&
                QDir(existing.value(K("codePath")).toString()).exists())
                continue; // up to date
            QString error;
            if (!installFrom(path, true, root.privileged, K("root"), &error))
                qCWarning(lcPm) << "cannot install" << path << error;
        }
    }

    // System packages removed by an OTA disappear; their data is kept.
    const QStringList known = m_packages.keys();
    for (const QString &pkg : known) {
        if (m_packages.value(pkg).value(K("system")).toBool() && !seenSystem.contains(pkg)) {
            qCInfo(lcPm) << "system package gone:" << pkg;
            m_packages.remove(pkg);
        }
    }
    save();
    qCInfo(lcPm) << m_packages.size() << "packages installed";
}

uid_t PackageManager::allocateUid() const
{
    uid_t uid = AID_APP_START;
    QSet<uid_t> used;
    for (const QJsonObject &p : m_packages)
        used.insert(uid_t(p.value(K("uid")).toInt()));
    while (used.contains(uid))
        ++uid;
    return uid;
}

void PackageManager::prepareDataDir(const QString &package, uid_t uid)
{
    const QString dir = Paths::dataData() + QLatin1Char('/') + package;
    QDir().mkpath(dir);
    QDir().mkpath(dir + QStringLiteral("/files"));
    QDir().mkpath(dir + QStringLiteral("/cache"));
    if (geteuid() == 0) {
        const QByteArray d = QFile::encodeName(dir);
        for (const char *sub : {"", "/files", "/cache"}) {
            const QByteArray p = d + sub;
            if (chown(p.constData(), uid, uid) != 0)
                qCWarning(lcPm) << "chown failed for" << p;
        }
        QFile::setPermissions(dir, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }
}

bool PackageManager::installFrom(const QString &apkgPath, bool system, bool privileged, const QString &installer,
                                 QString *error)
{
    Apkg apkg;
    if (!apkg.open(apkgPath) || !apkg.verify()) {
        *error = apkg.errorString();
        return false;
    }
    const QJsonObject manifest = apkg.manifest();
    const QString pkg = manifest.value(K("package")).toString();
    const QJsonObject existing = m_packages.value(pkg);
    if (!system && existing.value(K("system")).toBool()) {
        *error = QStringLiteral("%1 is a system package").arg(pkg);
        return false;
    }

    const QString appDir = Paths::dataApp() + QLatin1Char('/') + pkg;
    const QString codePath = appDir + QStringLiteral("/code");
    QDir().mkpath(appDir);
    if (!system) {
        const QString base = appDir + QStringLiteral("/base.apkg");
        if (QFileInfo(apkgPath).absoluteFilePath() != QFileInfo(base).absoluteFilePath()) {
            QFile::remove(base);
            if (!QFile::copy(apkgPath, base)) {
                *error = QStringLiteral("cannot copy package");
                return false;
            }
        }
    }
    if (!apkg.extractTo(codePath)) {
        *error = apkg.errorString();
        return false;
    }

    QStringList granted;
    for (const QJsonValue &v : manifest.value(K("permissions")).toArray()) {
        const QString perm = v.toString();
        if (privileged || permissions::isNormal(perm))
            granted.append(perm);
    }

    const uid_t uid = existing.isEmpty() ? allocateUid() : uid_t(existing.value(K("uid")).toInt());
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    QJsonObject record{
        {K("package"), pkg},
        {K("manifest"), manifest},
        {K("uid"), int(uid)},
        {K("source"), system ? apkgPath : appDir + QStringLiteral("/base.apkg")},
        {K("codePath"), codePath},
        {K("checksum"), QString::fromLatin1(apkg.checksum().toHex())},
        {K("system"), system},
        {K("privileged"), privileged},
        {K("installer"), installer},
        {K("granted"), QJsonArray::fromStringList(granted)},
        {K("firstInstall"), existing.isEmpty() ? now : existing.value(K("firstInstall")).toDouble()},
        {K("lastUpdate"), now},
    };
    m_packages.insert(pkg, record);
    prepareDataDir(pkg, uid);
    qCInfo(lcPm) << (existing.isEmpty() ? "installed" : "updated") << pkg << "uid" << uid;
    m_server->broadcast(K("packages.changed"), info(pkg));
    return true;
}

void PackageManager::uninstall(const QString &package)
{
    const QJsonObject record = m_packages.value(package);
    QDir(Paths::dataApp() + QLatin1Char('/') + package).removeRecursively();
    QDir(Paths::dataData() + QLatin1Char('/') + package).removeRecursively();
    m_packages.remove(package);
    save();
    Q_EMIT packageRemoved(package);
    m_server->broadcast(K("packages.removed"), QJsonObject{{K("package"), package}});
    qCInfo(lcPm) << "uninstalled" << package;
}

void PackageManager::save()
{
    QJsonObject db;
    for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it)
        db.insert(it.key(), it.value());
    saveJson(m_dbPath, db);
}

QJsonObject PackageManager::info(const QString &package) const
{
    const QJsonObject r = m_packages.value(package);
    if (r.isEmpty())
        return {};
    const QJsonObject m = r.value(K("manifest")).toObject();
    const QString code = r.value(K("codePath")).toString();

    QJsonArray widgets;
    for (const QJsonValue &v : m.value(K("widgets")).toArray()) {
        QJsonObject w = v.toObject();
        w.insert(K("qml"), code + QLatin1Char('/') + w.value(K("qml")).toString());
        w.insert(K("key"), package + QLatin1Char('/') + w.value(K("id")).toString());
        w.insert(K("package"), package);
        widgets.append(w);
    }
    return {
        {K("package"), package},
        {K("name"), m.value(K("name"))},
        {K("version"), m.value(K("version"))},
        {K("versionCode"), m.value(K("versionCode"))},
        {K("description"), m.value(K("description"))},
        {K("category"), m.value(K("category"))},
        {K("background"), m.value(K("background")).toString(QStringLiteral("#000000"))},
        {K("icon"), code + QLatin1Char('/') + m.value(K("icon")).toString()},
        {K("main"), code + QLatin1Char('/') + m.value(K("main")).toString()},
        {K("launcher"), m.value(K("launcher")).toObject().value(K("visible")).toBool(true)},
        {K("codePath"), code},
        {K("dataDir"), Paths::dataData() + QLatin1Char('/') + package},
        {K("uid"), r.value(K("uid"))},
        {K("system"), r.value(K("system"))},
        {K("privileged"), r.value(K("privileged"))},
        {K("installer"), r.value(K("installer"))},
        {K("removable"), !r.value(K("system")).toBool()},
        {K("permissions"), r.value(K("granted"))},
        {K("widgets"), widgets},
        {K("firstInstall"), r.value(K("firstInstall"))},
        {K("lastUpdate"), r.value(K("lastUpdate"))},
    };
}

QString PackageManager::packageForUid(uid_t uid) const
{
    if (uid < AID_APP_START)
        return {};
    for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it)
        if (uid_t(it.value().value(K("uid")).toInt()) == uid)
            return it.key();
    return {};
}

QStringList PackageManager::permissionsOf(const QString &package) const
{
    QStringList out;
    for (const QJsonValue &v : m_packages.value(package).value(K("granted")).toArray())
        out.append(v.toString());
    return out;
}

uid_t PackageManager::uidOf(const QString &package) const
{
    return uid_t(m_packages.value(package).value(K("uid")).toInt());
}

QJsonArray PackageManager::widgets() const
{
    QJsonArray out;
    for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it)
        for (const QJsonValue &w : info(it.key()).value(K("widgets")).toArray())
            out.append(w);
    return out;
}

QJsonValue PackageManager::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString pkg = params.value(K("package")).toString();

    if (call == QLatin1String("list")) {
        QJsonArray out;
        for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it)
            out.append(info(it.key()));
        return out;
    }
    if (call == QLatin1String("get")) {
        if (!m_packages.contains(pkg))
            throw RpcError{protocol::NotFound, QStringLiteral("no package %1").arg(pkg)};
        QJsonObject i = info(pkg);
        i.insert(K("sizeBytes"), double(directorySize(i.value(K("codePath")).toString()) +
                                        directorySize(i.value(K("dataDir")).toString())));
        return i;
    }
    if (call == QLatin1String("widgets"))
        return widgets();
    if (call == QLatin1String("install")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        QString error;
        const QString installer = caller.isSystem() ? K("system") : caller.package;
        if (!installFrom(params.value(K("path")).toString(), false, false, installer, &error))
            throw RpcError{protocol::Failed, error};
        save();
        return true;
    }
    if (call == QLatin1String("uninstall")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        if (!m_packages.contains(pkg))
            throw RpcError{protocol::NotFound, QStringLiteral("no package %1").arg(pkg)};
        if (m_packages.value(pkg).value(K("system")).toBool())
            throw RpcError{protocol::PermissionDenied, QStringLiteral("%1 was installed by root and cannot be removed").arg(pkg)};
        uninstall(pkg);
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
