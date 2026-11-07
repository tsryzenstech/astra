// SPDX-License-Identifier: Apache-2.0
#include "iconimages.h"

#include <QImageReader>
#include <QPainter>
#include <QQmlEngine>
#include <QQmlFile>
#include <QQuickImageProvider>

namespace astra::qml {

namespace {
const QString kProvider = QStringLiteral("astra-icon");

QString encode(const QUrl &url)
{
    return QString::fromLatin1(url.toEncoded().toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

// Ids are "r/<ratio>/<url>" and "t/<#rrggbbaa>/<url>", the URL in base64.
class Provider : public QQuickImageProvider
{
public:
    Provider()
        : QQuickImageProvider(QQuickImageProvider::Image)
    {
    }

    QImage requestImage(const QString &id, QSize *size, const QSize &requested) override
    {
        const QStringList parts = id.split(QLatin1Char('/'));
        if (parts.size() != 3)
            return {};
        const QUrl url = QUrl::fromEncoded(QByteArray::fromBase64(parts.at(2).toLatin1(), QByteArray::Base64UrlEncoding));

        QImageReader reader(QQmlFile::urlToLocalFileOrQrc(url));
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
    return new IconImages;
}

QUrl IconImages::rounded(const QUrl &source, qreal radiusRatio) const
{
    if (source.isEmpty())
        return {};
    return QUrl(QStringLiteral("image://%1/r/%2/%3").arg(kProvider, QString::number(radiusRatio, 'f', 4), encode(source)));
}

QUrl IconImages::tinted(const QUrl &source, const QColor &color) const
{
    if (source.isEmpty())
        return {};
    // Without the leading '#', which would end the URL's path.
    return QUrl(QStringLiteral("image://%1/t/%2/%3").arg(kProvider, color.name(QColor::HexArgb).mid(1), encode(source)));
}

} // namespace astra::qml
