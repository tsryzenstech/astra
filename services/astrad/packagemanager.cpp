// SPDX-License-Identifier: Apache-2.0
#include "packagemanager.h"
#include "dialogservice.h"
#include "jsonstore.h"
#include "permissions.h"

#include <astra/apkg.h>
#include <astra/global.h>
#include <astra/paths.h>
#include <astra/protocol.h>

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QLoggingCategory>
#include <QNetworkReply>

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

QStringList requestedOf(const QJsonObject &record)
{
    QStringList out;
    for (const QJsonValue &v : record.value(K("manifest")).toObject().value(K("permissions")).toArray())
        out.append(v.toString());
    return out;
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
                existing.value(K("privileged")).toBool() == root.privileged &&
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
    if (!existing.isEmpty() && manifest.value(K("versionCode")).toInt() <
                                   existing.value(K("manifest")).toObject().value(K("versionCode")).toInt() && !system) {
        *error = QStringLiteral("a newer version of %1 is installed").arg(pkg);
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

    // Runtime permissions keep the user's previous choices across updates.
    // Privileged apps get theirs pre-granted, like Android's system apps.
    QJsonObject runtime;
    const QJsonObject previous = existing.value(K("runtime")).toObject();
    for (const QJsonValue &v : manifest.value(K("permissions")).toArray()) {
        const QString perm = v.toString();
        if (!permissions::isRuntime(perm))
            continue;
        runtime.insert(perm, previous.contains(perm) ? previous.value(perm)
                                                     : QJsonValue(privileged ? K("granted") : K("ask")));
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
        {K("runtime"), runtime},
        {K("denials"), existing.value(K("denials")).toObject()},
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

QString PackageManager::displayName(const QString &package) const
{
    const QJsonObject m = m_packages.value(package).value(K("manifest")).toObject();
    const QString lang = m_language ? m_language() : QString();
    const QJsonObject names = m.value(K("names")).toObject();
    if (!lang.isEmpty() && names.contains(lang))
        return names.value(lang).toString();
    return m.value(K("name")).toString(package);
}

QJsonObject PackageManager::info(const QString &package) const
{
    const QJsonObject r = m_packages.value(package);
    if (r.isEmpty())
        return {};
    const QJsonObject m = r.value(K("manifest")).toObject();
    const QString code = r.value(K("codePath")).toString();
    const QString lang = m_language ? m_language() : QString();

    QJsonArray widgets;
    for (const QJsonValue &v : m.value(K("widgets")).toArray()) {
        QJsonObject w = v.toObject();
        w.insert(K("qml"), code + QLatin1Char('/') + w.value(K("qml")).toString());
        w.insert(K("key"), package + QLatin1Char('/') + w.value(K("id")).toString());
        w.insert(K("package"), package);
        const QJsonObject names = w.value(K("names")).toObject();
        if (names.contains(lang))
            w.insert(K("name"), names.value(lang));
        widgets.append(w);
    }
    const QJsonObject descriptions = m.value(K("descriptions")).toObject();
    return {
        {K("package"), package},
        {K("name"), displayName(package)},
        {K("version"), m.value(K("version"))},
        {K("versionCode"), m.value(K("versionCode"))},
        {K("description"), descriptions.contains(lang) ? descriptions.value(lang) : m.value(K("description"))},
        {K("category"), m.value(K("category"))},
        {K("background"), m.value(K("background")).toString(QStringLiteral("#000000"))},
        {K("appearance"), m.value(K("appearance")).toString(QStringLiteral("auto"))}, // "dark": always dark (camera, media)
        // File types the app opens ("Open with") and receives ("Share"), e.g. ["image/*"]
        {K("opens"), m.value(K("opens")).toArray()},
        {K("share"), m.value(K("share")).toArray()},
        {K("accent"), m.value(K("accent")).toString(QStringLiteral("#FF7A00"))},
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
        {K("permissions"), QJsonArray::fromStringList(permissionsOf(package))},
        {K("requested"), QJsonArray::fromStringList(requestedOf(r))},
        {K("widgets"), widgets},
        {K("firstInstall"), r.value(K("firstInstall"))},
        {K("lastUpdate"), r.value(K("lastUpdate"))},
    };
}

void PackageManager::installUrl(const QUrl &url, const QString &sha256, const QString &installer,
                                std::function<void(QString)> result)
{
    if (!m_network)
        m_network = new QNetworkAccessManager(this);
    QNetworkRequest request(url);
    request.setTransferTimeout(60000);
    QNetworkReply *r = m_network->get(request);
    connect(r, &QNetworkReply::finished, this, [this, r, sha256, installer, result] {
        r->deleteLater();
        if (r->error() != QNetworkReply::NoError) {
            result(r->errorString());
            return;
        }
        const QByteArray data = r->readAll();
        if (!sha256.isEmpty() &&
            QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex()) != sha256.toLower()) {
            result(K("The download is corrupted"));
            return;
        }
        const QString path = Paths::resolve(QStringLiteral("/data/local/tmp/market-%1.apkg").arg(QDateTime::currentMSecsSinceEpoch()));
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size()) {
            result(f.errorString());
            return;
        }
        f.close();
        QString error;
        const bool ok = installFrom(path, false, false, installer, &error);
        QFile::remove(path);
        if (ok)
            save();
        result(ok ? QString() : error);
    });
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
    const QJsonObject r = m_packages.value(package);
    const bool privileged = r.value(K("privileged")).toBool();
    const QJsonObject runtime = r.value(K("runtime")).toObject();
    QStringList out;
    for (const QString &perm : requestedOf(r)) {
        const permissions::Info *info = permissions::find(perm);
        if (!info)
            continue;
        switch (info->level) {
        case permissions::Level::Normal:
            out.append(perm);
            break;
        case permissions::Level::Privileged:
            if (privileged)
                out.append(perm);
            break;
        case permissions::Level::Runtime:
            if (runtime.value(perm).toString() == QLatin1String("granted"))
                out.append(perm);
            break;
        }
    }
    return out;
}

QList<gid_t> PackageManager::groupsOf(const QString &package) const
{
    QList<gid_t> groups{AID_GRAPHICS, AID_AUDIO};
    for (const QString &perm : permissionsOf(package)) {
        const permissions::Info *info = permissions::find(perm);
        if (info && info->gid && !groups.contains(info->gid))
            groups.append(info->gid);
    }
    return groups;
}

bool PackageManager::isGranted(const QString &package, const QString &permission) const
{
    return package.isEmpty() || permissionsOf(package).contains(permission);
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

void PackageManager::setRuntimeState(const QString &package, const QString &permission, const QString &state)
{
    QJsonObject r = m_packages.value(package);
    QJsonObject runtime = r.value(K("runtime")).toObject();
    const bool wasGranted = runtime.value(permission).toString() == QLatin1String("granted");
    runtime.insert(permission, state);
    r.insert(K("runtime"), runtime);
    if (state != QLatin1String("denied")) {
        QJsonObject denials = r.value(K("denials")).toObject();
        denials.remove(permission);
        r.insert(K("denials"), denials);
    }
    m_packages.insert(package, r);
    save();
    const permissions::Info *info = permissions::find(permission);
    const bool groupsChanged = info && info->gid && wasGranted != (state == QLatin1String("granted"));
    m_server->broadcast(K("packages.changed"), this->info(package));
    Q_EMIT permissionsChanged(package, groupsChanged);
}

void PackageManager::requestPermission(const QString &package, const QString &permission,
                                       std::function<void(bool, bool)> result)
{
    const QJsonObject r = m_packages.value(package);
    if (!requestedOf(r).contains(permission) || !permissions::isRuntime(permission)) {
        result(isGranted(package, permission), false);
        return;
    }
    const QString state = r.value(K("runtime")).toObject().value(permission).toString();
    if (state == QLatin1String("granted") || state == QLatin1String("denied") || !m_dialogs) {
        result(state == QLatin1String("granted"), false);
        return;
    }
    const permissions::Info *info = permissions::find(permission);
    const QJsonObject content{
        {K("kind"), K("permission")},
        {K("permission"), permission},
        {K("label"), QString::fromLatin1(info->label)},
        {K("icon"), QString::fromLatin1(info->icon)},
        {K("title"), QStringLiteral("Allow %1 to access %2?").arg(displayName(package), QString::fromLatin1(info->label).toLower())},
        {K("message"), QString()},
        {K("buttons"), QJsonArray{
             QJsonObject{{K("id"), K("deny")}, {K("label"), K("Don't allow")}, {K("style"), K("secondary")}},
             QJsonObject{{K("id"), K("allow")}, {K("label"), K("Allow")}, {K("style"), K("primary")}},
         }},
    };
    m_dialogs->show(package, content, K("deny"), [this, package, permission, info, result](const QString &button) {
        if (!m_packages.contains(package)) {
            result(false, false);
            return;
        }
        if (button == QLatin1String("allow")) {
            setRuntimeState(package, permission, K("granted"));
            result(true, info->gid != 0);
            return;
        }
        // The answer is final: only Settings > Apps > <app> changes it.
        // No answer (the app went away before the user decided) changes nothing.
        if (button == QLatin1String("deny"))
            setRuntimeState(package, permission, K("denied"));
        result(false, false);
    });
}

QJsonArray PackageManager::permissionList(const QString &package) const
{
    const QJsonObject r = m_packages.value(package);
    const QJsonObject runtime = r.value(K("runtime")).toObject();
    const QStringList granted = permissionsOf(package);
    QJsonArray out;
    for (const QString &perm : requestedOf(r)) {
        const permissions::Info *info = permissions::find(perm);
        if (!info)
            continue;
        const char *level = info->level == permissions::Level::Normal ? "normal"
                          : info->level == permissions::Level::Runtime ? "runtime" : "privileged";
        out.append(QJsonObject{
            {K("name"), perm},
            {K("label"), QString::fromLatin1(info->label)},
            {K("icon"), QString::fromLatin1(info->icon)},
            {K("level"), QString::fromLatin1(level)},
            {K("state"), info->level == permissions::Level::Runtime ? runtime.value(perm).toString(K("ask"))
                                                                     : QString(granted.contains(perm) ? "granted" : "denied")},
        });
    }
    return out;
}

QJsonValue PackageManager::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    const QString pkg = params.value(K("package")).toString();
    auto requireKnown = [this](const QString &p) {
        if (!m_packages.contains(p))
            throw RpcError{protocol::NotFound, QStringLiteral("no package %1").arg(p)};
    };

    if (call == QLatin1String("list")) {
        QJsonArray out;
        for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it)
            out.append(info(it.key()));
        return out;
    }
    if (call == QLatin1String("get")) {
        requireKnown(pkg);
        QJsonObject i = info(pkg);
        const double code = double(directorySize(i.value(K("codePath")).toString()));
        const double data = double(directorySize(i.value(K("dataDir")).toString()));
        i.insert(K("codeBytes"), code);
        i.insert(K("dataBytes"), data);
        i.insert(K("sizeBytes"), code + data);
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
    if (call == QLatin1String("installUrl")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        const QUrl url(params.value(K("url")).toString());
        if (!url.isValid() || url.scheme() != QLatin1String("https"))
            throw RpcError{protocol::InvalidParams, K("an https URL is required")};
        const PendingReply reply = caller.defer();
        installUrl(url, params.value(K("sha256")).toString(), caller.isSystem() ? K("system") : caller.package,
                   [reply](const QString &error) {
                       if (error.isEmpty())
                           reply.resolve(true);
                       else
                           reply.reject(protocol::Failed, error);
                   });
        return Deferred;
    }
    if (call == QLatin1String("uninstall")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        requireKnown(pkg);
        if (m_packages.value(pkg).value(K("system")).toBool())
            throw RpcError{protocol::PermissionDenied, QStringLiteral("System apps can't be uninstalled")};
        uninstall(pkg);
        return true;
    }
    if (call == QLatin1String("clearData")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        requireKnown(pkg);
        Q_EMIT dataCleared(pkg); // the activity manager stops the app first
        const QString dir = Paths::dataData() + QLatin1Char('/') + pkg;
        QDir(dir).removeRecursively();
        prepareDataDir(pkg, uidOf(pkg));
        return true;
    }

    // ---- permissions ------------------------------------------------------
    if (call == QLatin1String("permissions")) {
        const QString target = pkg.isEmpty() ? caller.package : pkg;
        if (target != caller.package)
            caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        requireKnown(target);
        return permissionList(target);
    }
    if (call == QLatin1String("checkPermission")) {
        return isGranted(caller.package, params.value(K("permission")).toString());
    }
    if (call == QLatin1String("requestPermission")) {
        if (caller.isSystem())
            return true;
        const PendingReply reply = caller.defer();
        requestPermission(caller.package, params.value(K("permission")).toString(), [reply](bool granted, bool restart) {
            reply.resolve(QJsonObject{{K("granted"), granted}, {K("restartRequired"), restart}});
        });
        return Deferred;
    }
    if (call == QLatin1String("setPermission")) {
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        requireKnown(pkg);
        const QString perm = params.value(K("permission")).toString();
        const QString state = params.value(K("state")).toString();
        if (!permissions::isRuntime(perm) || !requestedOf(m_packages.value(pkg)).contains(perm) ||
            (state != QLatin1String("granted") && state != QLatin1String("denied") && state != QLatin1String("ask")))
            throw RpcError{protocol::InvalidParams, QStringLiteral("not a runtime permission of %1").arg(pkg)};
        setRuntimeState(pkg, perm, state);
        return true;
    }
    if (call == QLatin1String("permissionApps")) {
        // Every app that asked for a permission, for Settings > Privacy.
        caller.require(QLatin1String(permissions::MANAGE_PACKAGES));
        const QString perm = params.value(K("permission")).toString();
        QJsonArray out;
        for (auto it = m_packages.cbegin(); it != m_packages.cend(); ++it) {
            if (!requestedOf(it.value()).contains(perm))
                continue;
            out.append(QJsonObject{{K("package"), it.key()},
                                   {K("name"), displayName(it.key())},
                                   {K("icon"), info(it.key()).value(K("icon"))},
                                   {K("state"), it.value().value(K("runtime")).toObject().value(perm).toString(K("granted"))}});
        }
        return out;
    }
    if (call == QLatin1String("permissionCatalog")) {
        QJsonArray out;
        for (const permissions::Info &i : permissions::all())
            if (i.level == permissions::Level::Runtime)
                out.append(QJsonObject{{K("name"), QString::fromLatin1(i.name)},
                                       {K("label"), QString::fromLatin1(i.label)},
                                       {K("icon"), QString::fromLatin1(i.icon)}});
        return out;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
