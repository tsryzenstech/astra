// SPDX-License-Identifier: Apache-2.0
#include "installerservice.h"
#include "permissions.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>

#include <memory>

Q_LOGGING_CATEGORY(lcInstaller, "astrad.installer")

namespace astrad {

using namespace astra;

namespace {
QString K(const char *s) { return QString::fromLatin1(s); }

// The only things that go into a command line: a device path from the list of disks, a label of plain
// characters, a format from a short list, a number.
QString cleanLabel(const QString &label, int max)
{
    QString out;
    for (const QChar c : label.left(max))
        if (c.isLetterOrNumber() || c == QLatin1Char(' ') || c == QLatin1Char('_') || c == QLatin1Char('-') || c == QLatin1Char('.'))
            out.append(c);
    return out.trimmed();
}

QString partName(const QString &disk, int n)
{
    return disk + (disk.back().isDigit() ? QStringLiteral("p") : QString()) + QString::number(n);
}

// mkfs command for a format name, or an empty string.
QString mkfs(const QString &format, const QString &device, const QString &label)
{
    const QString l = cleanLabel(label, 16);
    if (format == QLatin1String("ext4"))
        return QStringLiteral("mkfs.ext4 -q -F %1 %2").arg(l.isEmpty() ? QString() : QStringLiteral("-L '%1'").arg(l), device);
    if (format == QLatin1String("fat32"))
        return QStringLiteral("mkfs.vfat -F32 %1 %2").arg(l.isEmpty() ? QString() : QStringLiteral("-n '%1'").arg(l.toUpper().left(11)), device);
    if (format == QLatin1String("exfat"))
        return QStringLiteral("mkfs.exfat %1 %2").arg(l.isEmpty() ? QString() : QStringLiteral("-L '%1'").arg(l), device);
    if (format == QLatin1String("ntfs"))
        return QStringLiteral("mkfs.ntfs -q -F %1 %2").arg(l.isEmpty() ? QString() : QStringLiteral("-L '%1'").arg(l), device);
    if (format == QLatin1String("swap"))
        return QStringLiteral("mkswap %1 %2").arg(l.isEmpty() ? QString() : QStringLiteral("-L '%1'").arg(l), device);
    return {};
}
QString partType(const QString &format)
{
    if (format == QLatin1String("swap"))
        return QStringLiteral("S");
    if (format == QLatin1String("fat32") || format == QLatin1String("exfat") || format == QLatin1String("ntfs"))
        return QStringLiteral("0FC63DAF-8483-4772-8E79-3D69D8477DE4");   // Linux data: the type of a data partition
    return QStringLiteral("L");
}
} // namespace

InstallerService::InstallerService(Server *server, QObject *parent)
    : Service(parent)
    , m_server(server)
{
}

bool InstallerService::live() const
{
    return QFile::exists(Paths::resolve(QStringLiteral("/run/astra/live"))) || qEnvironmentVariableIntValue("ASTRA_INSTALLER") == 1;
}

bool InstallerService::validPath(const QString &path)
{
    static const QRegularExpression re(QStringLiteral("^/dev/[A-Za-z0-9_/-]{1,40}$"));
    return re.match(path).hasMatch() && !path.contains(QLatin1String(".."));
}

// lsblk, as the Disk Utility shows it: disks with their partitions; the disk the system runs from is marked.
QJsonArray InstallerService::disks() const
{
    QProcess p;
    p.start(K("lsblk"), {K("-J"), K("-b"), K("-p"), K("-o"), K("NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,RM,PTTYPE,PARTLABEL,PARTTYPE")});
    if (!p.waitForFinished(10000))
        return {};
    const QJsonArray devices = QJsonDocument::fromJson(p.readAllStandardOutput()).object().value(K("blockdevices")).toArray();
    QJsonArray out;
    for (const QJsonValue &v : devices) {
        const QJsonObject d = v.toObject();
        if (d.value(K("type")).toString() != QLatin1String("disk"))
            continue;
        const QString name = d.value(K("name")).toString();
        if (name.contains(QLatin1String("/zram")) || name.contains(QLatin1String("/ram")) || name.contains(QLatin1String("/loop")) || name.contains(QLatin1String("/sr")))
            continue;
        bool isLive = false;
        qint64 used = 0;
        QJsonArray parts;
        for (const QJsonValue &cv : d.value(K("children")).toArray()) {
            const QJsonObject c = cv.toObject();
            QString mount;
            for (const QJsonValue &m : c.value(K("mountpoints")).toArray())
                if (!m.isNull() && !m.toString().isEmpty()) {
                    mount = m.toString();
                    break;
                }
            if (mount.startsWith(QLatin1String("/run/live")) || mount == QLatin1String("/") || mount == QLatin1String("/cdrom"))
                isLive = true;
            const qint64 size = qint64(c.value(K("size")).toVariant().toLongLong());
            used += size;
            parts.append(QJsonObject{{K("path"), c.value(K("name"))}, {K("name"), QFileInfo(c.value(K("name")).toString()).fileName()},
                                     {K("size"), double(size)}, {K("fstype"), c.value(K("fstype")).toString()},
                                     {K("label"), c.value(K("label")).toString(c.value(K("partlabel")).toString())}, {K("mountpoint"), mount},
                                     // the EFI system partition other systems boot from (a dual boot reuses it)
                                     {K("esp"), c.value(K("parttype")).toString().compare(QStringLiteral("c12a7328-f81f-11d2-ba4b-00a0c93ec93b"), Qt::CaseInsensitive) == 0}});
        }
        const qint64 size = qint64(d.value(K("size")).toVariant().toLongLong());
        out.append(QJsonObject{{K("path"), name}, {K("name"), QFileInfo(name).fileName()}, {K("model"), d.value(K("model")).toString().trimmed()},
                               {K("size"), double(size)}, {K("removable"), d.value(K("rm")).toVariant().toBool()},
                               {K("partitionTable"), d.value(K("pttype")).toString()}, {K("live"), isLive},
                               {K("partitions"), parts}, {K("free"), double(qMax<qint64>(0, size - used - (2 << 20)))}});
    }
    return out;
}

bool InstallerService::knownDevice(const QString &path) const
{
    if (!validPath(path))
        return false;
    for (const QJsonValue &v : disks()) {
        const QJsonObject d = v.toObject();
        if (d.value(K("path")).toString() == path)
            return true;
        for (const QJsonValue &p : d.value(K("partitions")).toArray())
            if (p.toObject().value(K("path")).toString() == path)
                return true;
    }
    return false;
}

QJsonObject InstallerService::state() const
{
    return {{K("live"), live()}, {K("installing"), !m_install.isNull()}, {K("disks"), live() ? disks() : QJsonArray()}};
}

// Runs a script of validated pieces; answers `result` when it succeeds, its last words when it fails.
void InstallerService::runShell(const QString &script, const PendingReply &pending, const QJsonValue &result)
{
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this, [this, p, pending, result](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        if (st == QProcess::NormalExit && code == 0) {
            pending.resolve(result);
        } else {
            qCWarning(lcInstaller) << "failed:" << out;
            pending.reject(protocol::Failed, out.split(QLatin1Char('\n')).last().isEmpty() ? K("The operation failed") : out.split(QLatin1Char('\n')).last());
        }
        m_server->broadcast(K("installer.changed"), QJsonObject());
    });
    qCInfo(lcInstaller) << "running:" << script;
    p->start(K("/bin/sh"), {K("-c"), QStringLiteral("set -e; ") + script});
}

QJsonValue InstallerService::handle(const QString &call, const QJsonObject &params, const Caller &caller)
{
    caller.require(QLatin1String(permissions::MANAGE_DISKS));
    if (call == QLatin1String("state"))
        return state();
    if (!live())
        throw RpcError{protocol::PermissionDenied, K("Disks can only be changed from the recovery environment (start from the astraOS installer).")};
    if (call == QLatin1String("disks"))
        return disks();

    auto device = [&](const char *key) {
        const QString d = params.value(K(key)).toString();
        if (!knownDevice(d))
            throw RpcError{protocol::InvalidParams, QStringLiteral("unknown device %1").arg(d)};
        return d;
    };
    auto notLive = [&](const QString &dev) {
        // Never the disk the system is running from.
        for (const QJsonValue &v : disks()) {
            const QJsonObject d = v.toObject();
            if (!d.value(K("live")).toBool())
                continue;
            if (d.value(K("path")).toString() == dev)
                throw RpcError{protocol::PermissionDenied, K("This disk holds the system that is running: it cannot be changed now.")};
            for (const QJsonValue &p : d.value(K("partitions")).toArray())
                if (p.toObject().value(K("path")).toString() == dev)
                    throw RpcError{protocol::PermissionDenied, K("This disk holds the system that is running: it cannot be changed now.")};
        }
    };
    auto isDisk = [&](const QString &dev) {
        for (const QJsonValue &v : disks())
            if (v.toObject().value(K("path")).toString() == dev)
                return true;
        return false;
    };

    if (call == QLatin1String("erase")) {
        const QString dev = device("path");
        notLive(dev);
        const QString format = params.value(K("format")).toString(K("ext4"));
        const QString label = params.value(K("label")).toString();
        const PendingReply pending = caller.defer();
        QString script = QStringLiteral("for m in $(lsblk -nrpo MOUNTPOINT %1 | grep -v '^$' | sort -r); do umount \"$m\"; done; ").arg(dev);
        if (isDisk(dev)) {
            const QString part = partName(dev, 1);
            const QString fs = mkfs(format, part, label);
            if (fs.isEmpty())
                throw RpcError{protocol::InvalidParams, K("unknown format")};
            script += QStringLiteral("wipefs -a %1 >/dev/null; printf 'label: gpt\\ntype=%2\\n' | sfdisk -q %1; udevadm settle; "
                                     "for i in 1 2 3 4 5 6 7 8 9 10; do [ -b %3 ] && break; sleep 0.3; done; %4").arg(dev, partType(format), part, fs);
        } else {
            const QString fs = mkfs(format, dev, label);
            if (fs.isEmpty())
                throw RpcError{protocol::InvalidParams, K("unknown format")};
            script += QStringLiteral("wipefs -a %1 >/dev/null; %2").arg(dev, fs);
        }
        runShell(script, pending, true);
        return Deferred;
    }
    if (call == QLatin1String("createPartition")) {
        const QString disk = device("disk");
        notLive(disk);
        if (!isDisk(disk))
            throw RpcError{protocol::InvalidParams, K("not a disk")};
        const QString format = params.value(K("format")).toString(K("ext4"));
        const qint64 size = qint64(params.value(K("size")).toDouble());
        if (size < 0)
            throw RpcError{protocol::InvalidParams, K("size?")};
        int next = 1;
        for (const QJsonValue &v : disks())
            if (v.toObject().value(K("path")).toString() == disk)
                next = v.toObject().value(K("partitions")).toArray().size() + 1;
        const QString part = partName(disk, next);
        const QString fs = mkfs(format, part, params.value(K("label")).toString());
        if (fs.isEmpty())
            throw RpcError{protocol::InvalidParams, K("unknown format")};
        const PendingReply pending = caller.defer();
        const QString sizePart = size > 0 ? QStringLiteral("size=%1KiB, ").arg(size / 1024) : QString();
        QString script;
        if (params.value(K("table")).toString() == QLatin1String("new") || disks().isEmpty())
            script += QStringLiteral("[ -n \"$(lsblk -nro PTTYPE %1 | head -1)\" ] || echo 'label: gpt' | sfdisk -q %1; ").arg(disk);
        script += QStringLiteral("printf '%2type=%3\\n' | sfdisk -q --append %1; udevadm settle; for i in 1 2 3 4 5 6 7 8 9 10; do [ -b %4 ] && break; sleep 0.3; done; %5")
                      .arg(disk, sizePart, partType(format), part, fs);
        runShell(script, pending, true);
        return Deferred;
    }
    if (call == QLatin1String("deletePartition")) {
        const QString dev = device("path");
        notLive(dev);
        if (isDisk(dev))
            throw RpcError{protocol::InvalidParams, K("not a partition")};
        static const QRegularExpression num(QStringLiteral("^(.*?)p?([0-9]+)$"));
        const auto m = num.match(dev);
        if (!m.hasMatch())
            throw RpcError{protocol::InvalidParams, K("not a partition")};
        const PendingReply pending = caller.defer();
        runShell(QStringLiteral("umount %1 2>/dev/null || true; sfdisk -q --delete %2 %3; udevadm settle").arg(dev, m.captured(1), m.captured(2)), pending, true);
        return Deferred;
    }
    if (call == QLatin1String("mount") || call == QLatin1String("unmount")) {
        const QString dev = device("path");
        const PendingReply pending = caller.defer();
        const QString dir = QStringLiteral("/mnt/%1").arg(QFileInfo(dev).fileName());
        if (call == QLatin1String("mount"))
            runShell(QStringLiteral("mkdir -p %1; mountpoint -q %1 || mount %2 %1").arg(dir, dev), pending, QJsonObject{{K("mountpoint"), dir}});
        else
            runShell(QStringLiteral("umount %1").arg(dev), pending, true);
        return Deferred;
    }
    if (call == QLatin1String("install")) {
        if (m_install)
            throw RpcError{protocol::Failed, K("An installation is already running")};
        QStringList args;
        if (params.contains(K("disk"))) {
            const QString disk = device("disk");
            notLive(disk);
            args << K("--disk") << disk;
        } else {
            const QString root = device("root");
            notLive(root);
            args << K("--root") << root;
            if (params.contains(K("esp")))
                args << K("--esp") << device("esp");
            if (params.contains(K("bootdisk")))
                args << K("--bootdisk") << device("bootdisk");
            if (params.value(K("dual")).toBool())
                args << K("--dual");
        }
        if (params.contains(K("disk")) && params.value(K("dual")).toBool())
            throw RpcError{protocol::InvalidParams, K("a dual boot does not erase the disk")};
        const QString user = cleanLabel(params.value(K("user")).toString(K("astra")), 24).toLower().remove(QLatin1Char(' '));
        if (!user.isEmpty())
            args << K("--user") << user;
        const QString host = cleanLabel(params.value(K("hostname")).toString(), 40).remove(QLatin1Char(' ')).remove(QLatin1Char('.'));
        if (!host.isEmpty())
            args << K("--hostname") << host;
        if (qEnvironmentVariableIsSet("ASTRA_INSTALL_SOURCE"))
            args << K("--source") << qEnvironmentVariable("ASTRA_INSTALL_SOURCE");
        if (qEnvironmentVariableIntValue("ASTRA_INSTALL_NO_BOOTLOADER") == 1)
            args << K("--no-bootloader");
        auto *p = new QProcess(this);
        m_install = p;
        p->setProcessChannelMode(QProcess::MergedChannels);
        auto buffer = std::make_shared<QByteArray>();
        connect(p, &QProcess::readyRead, this, [this, p, buffer] {
            *buffer += p->readAll();
            int nl;
            while ((nl = buffer->indexOf('\n')) >= 0) {
                const QString line = QString::fromUtf8(buffer->left(nl)).trimmed();
                buffer->remove(0, nl + 1);
                if (line.startsWith(QLatin1String("PROGRESS "))) {
                    const QString rest = line.mid(9);
                    m_server->broadcast(K("installer.progress"), QJsonObject{{K("percent"), rest.section(QLatin1Char(' '), 0, 0).toInt()},
                                                                             {K("text"), rest.section(QLatin1Char(' '), 1)}});
                } else if (line.startsWith(QLatin1String("ERROR "))) {
                    m_server->broadcast(K("installer.error"), QJsonObject{{K("message"), line.mid(6)}});
                }
            }
        });
        connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus st) {
            p->deleteLater();
            if (st == QProcess::NormalExit && code == 0)
                m_server->broadcast(K("installer.finished"), QJsonObject());
            else
                m_server->broadcast(K("installer.error"), QJsonObject{{K("message"), K("The installation did not finish (code %1)").arg(code)}});
        });
        const QString script = Paths::resolve(QStringLiteral("/usr/lib/astra/installer/install.sh"));
        qCInfo(lcInstaller) << "installing:" << script << args;
        p->start(script, args);
        return true;
    }
    if (call == QLatin1String("cancel")) {
        if (m_install)
            m_install->kill();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
