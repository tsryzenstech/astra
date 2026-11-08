// SPDX-License-Identifier: Apache-2.0
#include "iconimages.h"

#include <QBuffer>
#include <QEventLoop>
#include <QHash>
#include <QImageReader>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPainter>
#include <QTimer>
#include <QQmlEngine>
#include <QQmlFile>
#include <QQuickImageProvider>

namespace astra::qml {

namespace {
const QString kProvider = QStringLiteral("astra-icon");
// Pictures from the network (Market's catalog): loaded on a loader thread.
const QString kNetProvider = QStringLiteral("astra-icon-net");

bool isRemote(const QUrl &url)
{
    return url.scheme() == QLatin1String("http") || url.scheme() == QLatin1String("https");
}

// A remote picture's bytes, downloaded once per run.
QByteArray download(const QUrl &url)
{
    static QMutex mutex;
    static QHash<QUrl, QByteArray> cache;
    {
        QMutexLocker lock(&mutex);
        if (cache.contains(url))
            return cache.value(url);
    }
    // On the loader thread: its own manager and a local loop.
    QNetworkAccessManager network;
    network.setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkRequest request(url);
    request.setTransferTimeout(15000);
    QNetworkReply *reply = network.get(request);
    QEventLoop loop;
    QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    loop.exec();
    const QByteArray data = reply->error() == QNetworkReply::NoError ? reply->readAll() : QByteArray();
    reply->deleteLater();
    QMutexLocker lock(&mutex);
    if (!data.isEmpty()) {
        if (cache.size() > 300)
            cache.clear();
        cache.insert(url, data);
    }
    return data;
}

QString encode(const QUrl &url)
{
    return QString::fromLatin1(url.toEncoded().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

// Ids are "r/<ratio>/<url>" and "t/<#rrggbbaa>/<url>", the URL in base64.
class Provider : public QQuickImageProvider
{
public:
    explicit Provider(bool network = false)
        : QQuickImageProvider(QQuickImageProvider::Image,
                              network ? QQmlImageProviderBase::ForceAsynchronousImageLoading : QQmlImageProviderBase::Flags())
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override
    {
        const QStringList parts = id.split(QLatin1Char('/'));
        if (parts.size() != 3)
            return {};
        const QUrl url = QUrl::fromEncoded(QByteArray::fromBase64(parts.at(2).toLatin1(), QByteArray::Base64UrlEncoding));

        QBuffer buffer;
        QImageReader reader;
        if (isRemote(url)) {
            buffer.setData(download(url));
            buffer.open(QIODevice::ReadOnly);
            reader.setDevice(&buffer);
        } else {
            reader.setFileName(QQmlFile::urlToLocalFileOrQrc(url));
        }
        const QSize wanted = requested.isValid() && !requested.isEmpty() ? requested : QSize(256, 256);
        const QSize natural = reader.size();
        reader.setScaledSize(natural.isValid() ? natural.scaled(wanted, Qt::KeepAspectRatio) : wanted);
        const QImage art = reader.read().convertToFormat(QImage::Format_ARGB32_Premultiplied);
        if (art.isNull())
            return {};

        QImage out(art.size(), QImage::Format_ARGB32_Premultiplied);
        out.fill(Qt::transparent);
        QPainter p(&out);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        if (parts.at(0) == QLatin1String("t")) {
            p.drawImage(0, 0, art);
            p.setCompositionMode(QPainter::CompositionMode_SourceIn);
            p.fillRect(out.rect(), QColor::fromString(parts.at(1).toLatin1().prepend('#')));
        } else {
            const qreal radius = parts.at(1).toDouble() * qMin(out.width(), out.height());
            p.setPen(Qt::NoPen);
            p.setBrush(Qt::white);
            p.drawRoundedRect(QRectF(out.rect()), radius, radius);
            p.setCompositionMode(QPainter::CompositionMode_SourceIn);
            p.drawImage(0, 0, art);
        }
        p.end();
        if (size)
            *size = out.size();
        return out;
    }
};
} // namespace

IconImages::IconImages(QObject *parent)
    : QObject(parent)
{
}

IconImages *IconImages::create(QQmlEngine *engine, QJSEngine *)
{
    // The engine owns the provider and, with no parent, this object.
    if (!engine->imageProvider(kProvider))
        engine->addImageProvider(kProvider, new Provider);
    if (!engine->imageProvider(kNetProvider))
        engine->addImageProvider(kNetProvider, new Provider(true));
    return new IconImages;
}

QUrl IconImages::rounded(const QUrl &source, qreal radiusRatio) const
{
    if (source.isEmpty())
        return {};
    return QUrl(QStringLiteral("image://%1/r/%2/%3").arg(isRemote(source) ? kNetProvider : kProvider,
                                                          QString::number(radiusRatio, 'f', 4), encode(source)));
}

QUrl IconImages::tinted(const QUrl &source, const QColor &color) const
{
    if (source.isEmpty())
        return {};
    // Without the leading '#', which would end the URL's path.
    return QUrl(QStringLiteral("image://%1/t/%2/%3").arg(isRemote(source) ? kNetProvider : kProvider,
                                                          color.name(QColor::HexArgb).mid(1), encode(source)));
}

} // namespace astra::qml
