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

// Android's launcher icons come with their own shape: a circle, a drop, a
// squircle with a margin around it. Artwork like that (transparent corners) is
// cut to what it draws and put on the colour of its edge, so that it fills
// astraOS's icon shape like any other app's.
bool adaptAndroidArt(const QImage &art, QImage *adapted, QColor *backdrop)
{
    const int w = art.width(), h = art.height();
    if (w < 16 || h < 16 || !art.hasAlphaChannel() || qAlpha(art.pixel(1, 1)) > 40 || qAlpha(art.pixel(w - 2, h - 2)) > 40)
        return false;
    int x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (int y = 0; y < h; ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(art.constScanLine(y));
        for (int x = 0; x < w; ++x) {
            if (qAlpha(line[x]) > 48) {
                x0 = qMin(x0, x); x1 = qMax(x1, x); y0 = qMin(y0, y); y1 = qMax(y1, y);
            }
        }
    }
    if (x1 - x0 < 8 || y1 - y0 < 8)
        return false;
    // A square around the drawing.
    const int side = qMax(x1 - x0, y1 - y0) + 1;
    const QPoint centre((x0 + x1) / 2, (y0 + y1) / 2);
    QRect crop(centre.x() - side / 2, centre.y() - side / 2, side, side);
    crop = crop.intersected(art.rect());
    *adapted = art.copy(crop);
    // The colour along the edge of the drawing: its own backdrop.
    qint64 r = 0, g = 0, b = 0, n = 0;
    const int cw = adapted->width(), ch = adapted->height();
    auto take = [&](int x, int y) {
        const QRgb c = adapted->pixel(qBound(0, x, cw - 1), qBound(0, y, ch - 1));
        if (qAlpha(c) > 220) {
            r += qRed(c); g += qGreen(c); b += qBlue(c); ++n;
        }
    };
    for (int i = cw / 4; i < cw - cw / 4; ++i) { take(i, 1); take(i, ch - 2); }
    for (int i = ch / 4; i < ch - ch / 4; ++i) { take(1, i); take(cw - 2, i); }
    if (n == 0) {
        // A drawing that does not touch its frame (a glyph alone): the average colour around its middle.
        take(cw / 2, ch / 2);
    }
    *backdrop = n ? QColor(int(r / n), int(g / n), int(b / n)) : QColor(Qt::white);
    return true;
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
        QImage adapted;
        QColor backdrop;
        if (parts.at(0) == QLatin1String("r") && adaptAndroidArt(art, &adapted, &backdrop))
            p.setBrush(backdrop);
        p.setRenderHint(QPainter::Antialiasing);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        if (parts.at(0) == QLatin1String("t")) {
            p.drawImage(0, 0, art);
            p.setCompositionMode(QPainter::CompositionMode_SourceIn);
            p.fillRect(out.rect(), QColor::fromString(parts.at(1).toLatin1().prepend('#')));
        } else {
            const qreal radius = parts.at(1).toDouble() * qMin(out.width(), out.height());
            p.setPen(Qt::NoPen);
            p.setBrush(adapted.isNull() ? QBrush(Qt::white) : QBrush(backdrop));
            p.drawRoundedRect(QRectF(out.rect()), radius, radius);
            p.setCompositionMode(QPainter::CompositionMode_SourceIn);
            if (adapted.isNull()) {
                p.drawImage(0, 0, art);
            } else {
                // The backdrop under the shape, the artwork over it.
                p.setCompositionMode(QPainter::CompositionMode_SourceOver);
                QImage tile(out.size(), QImage::Format_ARGB32_Premultiplied);
                tile.fill(backdrop);
                QPainter t(&tile);
                t.setRenderHint(QPainter::SmoothPixmapTransform);
                t.drawImage(QRect(QPoint(0, 0), out.size()), adapted);
                t.end();
                QImage shape(out.size(), QImage::Format_ARGB32_Premultiplied);
                shape.fill(Qt::transparent);
                QPainter sp(&shape);
                sp.setRenderHint(QPainter::Antialiasing);
                sp.setPen(Qt::NoPen);
                sp.setBrush(Qt::white);
                sp.drawRoundedRect(QRectF(shape.rect()), radius, radius);
                sp.setCompositionMode(QPainter::CompositionMode_SourceIn);
                sp.drawImage(0, 0, tile);
                sp.end();
                p.drawImage(0, 0, shape);
            }
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
