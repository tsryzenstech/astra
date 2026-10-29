// SPDX-License-Identifier: Apache-2.0
#include "files.h"

#include <astra/paths.h>

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QStorageInfo>
#include <QUrl>

namespace astra::qml {

FileSystem::FileSystem(QObject *parent)
    : QObject(parent)
{
}

QString FileSystem::home() const
{
    return Paths::userMedia();
}

QString FileSystem::appData() const
{
    return QDir::homePath();
}

bool FileSystem::allowed(const QString &path) const
{
    // Resolve what exists of the path (a new file's parent) without
    // following links out of the allowed roots.
    QFileInfo f(path);
    QString p = f.exists() ? f.canonicalFilePath() : QFileInfo(f.absolutePath()).canonicalFilePath();
    if (p.isEmpty())
        return false;
    for (const QString &root : {home(), appData()}) {
        const QString r = QFileInfo(root).canonicalFilePath();
        if (!r.isEmpty() && (p == r || p.startsWith(r + QLatin1Char('/'))))
            return true;
    }
    return false;
}

QVariantMap FileSystem::entry(const QFileInfo &f) const
{
    return {
        {QStringLiteral("name"), f.fileName()},
        {QStringLiteral("path"), f.absoluteFilePath()},
        {QStringLiteral("url"), QUrl::fromLocalFile(f.absoluteFilePath())},
        {QStringLiteral("dir"), f.isDir()},
        {QStringLiteral("size"), double(f.isDir() ? 0 : f.size())},
        {QStringLiteral("count"), f.isDir() ? QDir(f.absoluteFilePath()).entryList(QDir::AllEntries | QDir::NoDotAndDotDot).size() : 0},
        {QStringLiteral("modified"), f.lastModified()},
        {QStringLiteral("mime"), f.isDir() ? QStringLiteral("inode/directory") : mimeType(f.absoluteFilePath())},
        {QStringLiteral("hidden"), f.isHidden()},
    };
}

QVariantList FileSystem::list(const QString &dir, bool showHidden) const
{
    QVariantList out;
    if (!allowed(dir))
        return out;
    QDir d(dir);
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (showHidden)
        filters |= QDir::Hidden;
    for (const QFileInfo &f : d.entryInfoList(filters, QDir::DirsFirst | QDir::Name | QDir::IgnoreCase))
        out.append(entry(f));
    return out;
}

QVariantMap FileSystem::info(const QString &path) const
{
    if (!allowed(path))
        return {};
    QVariantMap m = entry(QFileInfo(path));
    if (QFileInfo(path).isDir()) {
        qint64 total = 0;
        QDirIterator it(path, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            total += it.fileInfo().size();
        }
        m.insert(QStringLiteral("size"), double(total));
    }
    m.insert(QStringLiteral("created"), QFileInfo(path).birthTime());
    return m;
}

QVariantList FileSystem::search(const QString &root, const QString &query, int limit) const
{
    QVariantList out;
    if (!allowed(root) || query.trimmed().isEmpty())
        return out;
    QDirIterator it(root, QDir::AllEntries | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext() && out.size() < limit) {
        it.next();
        if (it.fileName().contains(query.trimmed(), Qt::CaseInsensitive) && !it.filePath().contains(QLatin1String("/.")))
            out.append(entry(it.fileInfo()));
    }
    return out;
}

QVariantList FileSystem::recent(int limit) const
{
    QList<QFileInfo> files;
    QDirIterator it(home(), QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        if (!it.filePath().contains(QLatin1String("/.")))
            files.append(it.fileInfo());
    }
    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) { return a.lastModified() > b.lastModified(); });
    QVariantList out;
    for (int i = 0; i < files.size() && i < limit; ++i)
        out.append(entry(files.at(i)));
    return out;
}

QString FileSystem::uniqueName(const QString &dir, const QString &name) const
{
    QString candidate = name;
    const QFileInfo base(name);
    for (int n = 2; QFileInfo::exists(dir + QLatin1Char('/') + candidate); ++n)
        candidate = base.suffix().isEmpty() ? QStringLiteral("%1 %2").arg(name).arg(n)
                                            : QStringLiteral("%1 %2.%3").arg(base.completeBaseName()).arg(n).arg(base.suffix());
    return candidate;
}

QString FileSystem::mkdir(const QString &dir, const QString &name)
{
    if (!allowed(dir) || name.contains(QLatin1Char('/')) || name.trimmed().isEmpty())
        return {};
    const QString path = dir + QLatin1Char('/') + uniqueName(dir, name.trimmed());
    if (!QDir().mkdir(path))
        return {};
    Q_EMIT changed(dir);
    return path;
}

QString FileSystem::rename(const QString &path, const QString &name)
{
    if (!allowed(path) || name.contains(QLatin1Char('/')) || name.trimmed().isEmpty())
        return {};
    const QFileInfo f(path);
    const QString target = f.absolutePath() + QLatin1Char('/') + name.trimmed();
    if (QFileInfo::exists(target) || !QFile::rename(path, target))
        return {};
    Q_EMIT changed(f.absolutePath());
    return target;
}

int FileSystem::remove(const QVariantList &paths)
{
    int n = 0;
    QString dir;
    for (const QVariant &v : paths) {
        const QString p = v.toString();
        if (!allowed(p) || QFileInfo(p).canonicalFilePath() == QFileInfo(home()).canonicalFilePath())
            continue;
        const QFileInfo f(p);
        dir = f.absolutePath();
        if (f.isDir() ? QDir(p).removeRecursively() : QFile::remove(p))
            ++n;
    }
    if (n)
        Q_EMIT changed(dir);
    return n;
}

static bool copyTree(const QString &from, const QString &to)
{
    if (!QFileInfo(from).isDir())
        return QFile::copy(from, to);
    if (!QDir().mkpath(to))
        return false;
    for (const QFileInfo &f : QDir(from).entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden))
        if (!copyTree(f.absoluteFilePath(), to + QLatin1Char('/') + f.fileName()))
            return false;
    return true;
}

int FileSystem::copy(const QVariantList &paths, const QString &dir)
{
    if (!allowed(dir))
        return 0;
    int n = 0;
    for (const QVariant &v : paths) {
        const QString p = v.toString();
        if (!allowed(p) || dir.startsWith(QFileInfo(p).canonicalFilePath() + QLatin1Char('/')))
            continue; // never into itself
        if (copyTree(p, dir + QLatin1Char('/') + uniqueName(dir, QFileInfo(p).fileName())))
            ++n;
    }
    if (n)
        Q_EMIT changed(dir);
    return n;
}

int FileSystem::move(const QVariantList &paths, const QString &dir)
{
    if (!allowed(dir))
        return 0;
    int n = 0;
    for (const QVariant &v : paths) {
        const QString p = v.toString();
        if (!allowed(p) || QFileInfo(p).absolutePath() == QFileInfo(dir).absoluteFilePath() ||
            dir.startsWith(QFileInfo(p).canonicalFilePath() + QLatin1Char('/')))
            continue;
        const QString target = dir + QLatin1Char('/') + uniqueName(dir, QFileInfo(p).fileName());
        // rename() fails across filesystems: copy, then remove.
        if (QFile::rename(p, target) || (copyTree(p, target) && (QFileInfo(p).isDir() ? QDir(p).removeRecursively() : QFile::remove(p)))) {
            ++n;
            Q_EMIT changed(QFileInfo(p).absolutePath());
        }
    }
    if (n)
        Q_EMIT changed(dir);
    return n;
}

QString FileSystem::readText(const QString &path, int maxBytes) const
{
    QFile f(path);
    if (!allowed(path) || !f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.read(maxBytes));
}

bool FileSystem::writeText(const QString &path, const QString &text)
{
    QFile f(path);
    if (!allowed(path) || !f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    f.write(text.toUtf8());
    Q_EMIT changed(QFileInfo(path).absolutePath());
    return true;
}

QString FileSystem::mimeType(const QString &path) const
{
    static QMimeDatabase db;
    if (path.endsWith(QLatin1String(".apkg"), Qt::CaseInsensitive))
        return QStringLiteral("application/x-astra-apkg");
    return db.mimeTypeForFile(path).name();
}

QVariantMap FileSystem::usage() const
{
    const QStorageInfo s(home());
    return {{QStringLiteral("total"), double(s.bytesTotal())}, {QStringLiteral("free"), double(s.bytesAvailable())}};
}

} // namespace astra::qml
