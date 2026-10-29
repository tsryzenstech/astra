// SPDX-License-Identifier: Apache-2.0
#include "services.h"
#include "common.h"

#include <astra/client.h>
#include <astra/paths.h>

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QImageReader>
#include <QUrl>
#include <thread>
#include <QDateTime>
#include <QJSEngine>
#include <QPointer>
#include <QJsonDocument>
#include <QJsonObject>

namespace astra::qml {

WeatherInfo::WeatherInfo(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("weather")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            refresh();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("weather.changed")) {
            m_current = data.toObject().toVariantMap();
            Q_EMIT currentChanged();
        }
    });
    if (c->isConnected())
        refresh();
}

void WeatherInfo::refresh()
{
    Client::instance()->call(QStringLiteral("weather.current"), {}, [this](const QJsonValue &r, const QString &) {
        m_current = r.toObject().toVariantMap();
        Q_EMIT currentChanged();
    });
}

LockState::LockState(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("lock")});
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            reload();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &) {
        if (name == QLatin1String("lock.changed"))
            reload();
    });
    if (c->isConnected())
        reload();
}

void LockState::reload()
{
    Client::instance()->call(QStringLiteral("lock.state"), {}, [this](const QJsonValue &r, const QString &) {
        const QJsonObject o = r.toObject();
        m_hasPin = o.value(QLatin1String("hasPin")).toBool();
        m_length = o.value(QLatin1String("length")).toInt();
        Q_EMIT changed();
    });
}

void LockState::verify(const QString &pin, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("lock.verify"), {{QStringLiteral("pin"), pin}},
                             [this, callback](const QJsonValue &r, const QString &e) { invokeCallback(this, callback, r.toBool(), e); });
}

void LockState::setPin(const QString &current, const QString &pin, const QJSValue &callback)
{
    Client::instance()->call(QStringLiteral("lock.setPin"), {{QStringLiteral("current"), current}, {QStringLiteral("pin"), pin}},
                             [this, callback](const QJsonValue &r, const QString &e) {
                                 reload();
                                 invokeCallback(this, callback, r.toBool(), e);
                             });
}

ApplicationInfo::ApplicationInfo(QObject *parent)
    : QObject(parent)
{
    m_args = QJsonDocument::fromJson(qgetenv("ASTRA_LAUNCH_ARGS")).object().toVariantMap();
    connect(Client::instance(), &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name != QLatin1String("activity.intent"))
            return;
        m_args = data.toObject().toVariantMap();
        Q_EMIT argsChanged();
        Q_EMIT intent(m_args);
    });
}

QString ApplicationInfo::packageName() const
{
    return qEnvironmentVariable("ASTRA_PACKAGE");
}

QString ApplicationInfo::dataDir() const
{
    return QDir::homePath();
}

QString ApplicationInfo::mediaDir() const
{
    return Paths::userMedia();
}

void ApplicationInfo::quit()
{
    QCoreApplication::quit();
}

static bool insideMedia(const QString &path)
{
    const QString root = QFileInfo(Paths::userMedia()).canonicalFilePath();
    const QString p = QFileInfo(path).canonicalFilePath();
    return !root.isEmpty() && p.startsWith(root + QLatin1Char('/'));
}

QVariantList ApplicationInfo::media(const QStringList &nameFilters) const
{
    const_cast<ApplicationInfo *>(this)->watchMedia();
    QList<QFileInfo> files;
    QDirIterator it(Paths::userMedia(), nameFilters, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        if (!it.filePath().contains(QLatin1String("/.")))  // skip hidden folders (.thumbnails, .trash)
            files.append(it.fileInfo());
    }
    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) { return a.lastModified() > b.lastModified(); });
    QVariantList out;
    const QString root = Paths::userMedia();
    for (const QFileInfo &f : std::as_const(files)) {
        const QString suffix = f.suffix().toLower();
        QString folder = f.absolutePath().mid(root.size() + 1);
        out.append(QVariantMap{
            {QStringLiteral("path"), f.absoluteFilePath()},
            {QStringLiteral("url"), QUrl::fromLocalFile(f.absoluteFilePath())},
            {QStringLiteral("name"), f.fileName()},
            {QStringLiteral("folder"), folder},
            {QStringLiteral("modified"), f.lastModified()},
            {QStringLiteral("size"), double(f.size())},
            {QStringLiteral("video"), suffix == QLatin1String("mp4") || suffix == QLatin1String("webm") || suffix == QLatin1String("mkv")},
        });
    }
    return out;
}

void ApplicationInfo::mediaAsync(const QStringList &nameFilters, const QJSValue &callback)
{
    watchMedia();
    struct Entry { QString path, folder; QDateTime modified; qint64 size; };
    const QString root = Paths::userMedia();
    // The callback stays on this thread; the worker only carries its id.
    const int id = ++m_mediaRequest;
    m_mediaCallbacks.insert(id, callback);
    QPointer<ApplicationInfo> self(this);
    std::thread([self, root, nameFilters, id] {
        QList<Entry> files;
        QDirIterator it(root, nameFilters, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            const QString path = it.filePath();
            if (path.contains(QLatin1String("/.")) || path.contains(QLatin1String("/Android/")))
                continue; // hidden folders (.thumbnails, .trash) and app data
            const QFileInfo f = it.fileInfo();
            files.append({f.absoluteFilePath(), f.absolutePath().mid(root.size() + 1), f.lastModified(), f.size()});
        }
        std::sort(files.begin(), files.end(), [](const Entry &a, const Entry &b) { return a.modified > b.modified; });
        QMetaObject::invokeMethod(qApp, [self, files, id] {
            if (!self)
                return;
            const QJSValue callback = self->m_mediaCallbacks.take(id);
            if (!callback.isCallable())
                return;
            QJSEngine *engine = qjsEngine(self.data());
            if (!engine)
                return;
            QJSValue list = engine->newArray(uint(files.size()));
            quint32 i = 0;
            for (const Entry &e : files) {
                const QString suffix = QFileInfo(e.path).suffix().toLower();
                list.setProperty(i++, engine->toScriptValue(QVariantMap{
                    {QStringLiteral("path"), e.path},
                    {QStringLiteral("url"), QUrl::fromLocalFile(e.path)},
                    {QStringLiteral("name"), QFileInfo(e.path).fileName()},
                    {QStringLiteral("folder"), e.folder},
                    {QStringLiteral("modified"), e.modified},
                    {QStringLiteral("size"), double(e.size)},
                    {QStringLiteral("video"), suffix == QLatin1String("mp4") || suffix == QLatin1String("webm") || suffix == QLatin1String("mkv")}}));
            }
            QJSValue cb = callback;
            cb.call({list});
        }, Qt::QueuedConnection);
    }).detach();
}

bool ApplicationInfo::removeMedia(const QString &path)
{
    if (!insideMedia(path))
        return false;
    const bool ok = QFile::remove(path);
    if (ok)
        Q_EMIT mediaChanged();
    return ok;
}

QVariantMap ApplicationInfo::imageInfo(const QString &path) const
{
    if (!insideMedia(path))
        return {};
    const QFileInfo f(path);
    const QSize size = QImageReader(path).size();
    return {{QStringLiteral("width"), size.width()}, {QStringLiteral("height"), size.height()},
            {QStringLiteral("size"), double(f.size())}, {QStringLiteral("modified"), f.lastModified()}};
}

// New screenshots, photos and downloads show up without a refresh.
void ApplicationInfo::watchMedia()
{
    if (m_watcher)
        return;
    m_watcher = new QFileSystemWatcher(this);
    const QString root = Paths::userMedia();
    for (const char *dir : {"", "/DCIM", "/DCIM/Camera", "/Pictures", "/Pictures/Screenshots", "/Download", "/Movies"})
        if (QFileInfo::exists(root + QLatin1String(dir)))
            m_watcher->addPath(root + QLatin1String(dir));
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &ApplicationInfo::mediaChanged);
}

} // namespace astra::qml
