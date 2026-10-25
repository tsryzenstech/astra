// SPDX-License-Identifier: Apache-2.0
#include "astra/apkg.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSaveFile>
#include <QtEndian>

#include <zlib.h>

namespace astra {

namespace {
constexpr char kMagic[] = "ASTRAPKG";
constexpr char kTrailerMagic[] = "APKGEND"; // + NUL
constexpr quint16 kFormatVersion = 1;
constexpr int kHeaderSize = 64;
constexpr int kEntrySize = 64;
constexpr int kTrailerSize = 40;

template<typename T>
T le(const char *p)
{
    return qFromLittleEndian<T>(reinterpret_cast<const uchar *>(p));
}
} // namespace

bool Apkg::fail(const QString &error)
{
    m_error = error;
    return false;
}

bool Apkg::open(const QString &fileName)
{
    m_entries.clear();
    m_manifest = {};
    QFile f(fileName);
    if (!f.open(QIODevice::ReadOnly))
        return fail(QStringLiteral("cannot open %1: %2").arg(fileName, f.errorString()));
    m_blob = f.readAll();

    const qint64 size = m_blob.size();
    if (size < kHeaderSize + kTrailerSize)
        return fail(QStringLiteral("file too small"));
    const char *h = m_blob.constData();
    if (memcmp(h, kMagic, 8) != 0)
        return fail(QStringLiteral("not an astraOS package"));
    if (le<quint16>(h + 8) != kFormatVersion)
        return fail(QStringLiteral("unsupported package format version"));

    const quint32 manifestOffset = le<quint32>(h + 16);
    const quint32 manifestSize = le<quint32>(h + 20);
    const quint32 indexOffset = le<quint32>(h + 24);
    const quint32 indexSize = le<quint32>(h + 28);
    const quint32 count = le<quint32>(h + 32);
    m_dataOffset = le<quint64>(h + 40);
    const quint64 dataSize = le<quint64>(h + 48);

    const quint64 end = quint64(size - kTrailerSize);
    if (quint64(manifestOffset) + manifestSize > end || quint64(indexOffset) + indexSize > end ||
        m_dataOffset + dataSize > end)
        return fail(QStringLiteral("section out of bounds"));

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(m_blob.mid(manifestOffset, manifestSize), &err);
    if (!doc.isObject())
        return fail(QStringLiteral("invalid manifest: %1").arg(err.errorString()));
    m_manifest = doc.object();

    quint64 pos = indexOffset;
    const quint64 indexEnd = quint64(indexOffset) + indexSize;
    for (quint32 i = 0; i < count; ++i) {
        if (pos + kEntrySize > indexEnd)
            return fail(QStringLiteral("index truncated"));
        const char *e = h + pos;
        Entry entry;
        const quint16 pathLen = le<quint16>(e);
        entry.compression = quint8(e[2]);
        entry.mode = le<quint32>(e + 4);
        entry.offset = le<quint64>(e + 8);
        entry.storedSize = le<quint64>(e + 16);
        entry.size = le<quint64>(e + 24);
        entry.sha256 = QByteArray(e + 32, 32);
        pos += kEntrySize;
        if (pos + pathLen > indexEnd)
            return fail(QStringLiteral("index truncated"));
        entry.path = QString::fromUtf8(h + pos, pathLen);
        pos += pathLen;

        if (entry.path.startsWith(QLatin1Char('/')) || entry.path.split(QLatin1Char('/')).contains(QStringLiteral("..")))
            return fail(QStringLiteral("unsafe path %1").arg(entry.path));
        if (entry.offset + entry.storedSize > dataSize)
            return fail(QStringLiteral("entry %1 out of bounds").arg(entry.path));
        m_entries.append(entry);
    }
    return validateManifest(m_manifest, &m_error);
}

QByteArray Apkg::checksum() const
{
    return m_blob.mid(m_blob.size() - kTrailerSize, 32);
}

bool Apkg::verify()
{
    const char *t = m_blob.constData() + m_blob.size() - kTrailerSize;
    if (memcmp(t + 32, kTrailerMagic, 8) != 0)
        return fail(QStringLiteral("bad trailer"));
    const QByteArray digest = QCryptographicHash::hash(
        QByteArrayView(m_blob.constData(), m_blob.size() - kTrailerSize), QCryptographicHash::Sha256);
    if (digest != QByteArray(t, 32))
        return fail(QStringLiteral("package checksum mismatch"));
    for (const Entry &e : std::as_const(m_entries)) {
        const QByteArray data = read(e);
        if (data.size() != qsizetype(e.size) || QCryptographicHash::hash(data, QCryptographicHash::Sha256) != e.sha256)
            return fail(QStringLiteral("checksum mismatch for %1").arg(e.path));
    }
    return true;
}

QByteArray Apkg::read(const Entry &entry)
{
    const QByteArray stored = m_blob.mid(qsizetype(m_dataOffset + entry.offset), qsizetype(entry.storedSize));
    if (entry.compression == 0)
        return stored;
    if (entry.compression != 1)
        return {};
    QByteArray out(qsizetype(entry.size), Qt::Uninitialized);
    uLongf outLen = uLongf(entry.size);
    if (uncompress(reinterpret_cast<Bytef *>(out.data()), &outLen,
                   reinterpret_cast<const Bytef *>(stored.constData()), uLong(stored.size())) != Z_OK ||
        outLen != entry.size)
        return {};
    return out;
}

bool Apkg::extractTo(const QString &directory)
{
    QDir dir(directory);
    if (dir.exists() && !dir.removeRecursively())
        return fail(QStringLiteral("cannot clean %1").arg(directory));
    for (const Entry &e : std::as_const(m_entries)) {
        const QString target = dir.filePath(e.path);
        QDir().mkpath(QFileInfo(target).absolutePath());
        QSaveFile out(target);
        if (!out.open(QIODevice::WriteOnly))
            return fail(QStringLiteral("cannot write %1").arg(target));
        out.write(read(e));
        if (!out.commit())
            return fail(QStringLiteral("cannot write %1").arg(target));
        QFile::setPermissions(target, (e.mode & 0100) ? QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner |
                                                             QFile::ReadGroup | QFile::ExeGroup | QFile::ReadOther | QFile::ExeOther
                                                       : QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
    }
    return true;
}

bool Apkg::validateManifest(const QJsonObject &m, QString *error)
{
    static const QRegularExpression packageRe(QStringLiteral("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$"));
    auto bad = [error](const QString &why) {
        if (error)
            *error = QStringLiteral("manifest: ") + why;
        return false;
    };
    if (!packageRe.match(m.value(QLatin1String("package")).toString()).hasMatch())
        return bad(QStringLiteral("invalid package name"));
    for (const char *key : {"name", "version", "main", "icon"})
        if (!m.value(QLatin1String(key)).isString())
            return bad(QStringLiteral("missing %1").arg(QLatin1String(key)));
    if (m.value(QLatin1String("versionCode")).toInt() < 1)
        return bad(QStringLiteral("invalid versionCode"));
    for (const QJsonValue &w : m.value(QLatin1String("widgets")).toArray()) {
        const QJsonObject o = w.toObject();
        if (!o.value(QLatin1String("id")).isString() || !o.value(QLatin1String("qml")).isString())
            return bad(QStringLiteral("invalid widget declaration"));
    }
    return true;
}

} // namespace astra
