// SPDX-License-Identifier: Apache-2.0
#include "imagetools.h"

#include <QUrl>

#include <array>

namespace astra::qml {

ImageTools::ImageTools(QObject *parent)
    : QObject(parent)
{
}

QImage ImageTools::load(const QString &source)
{
    if (source.startsWith(QLatin1String("data:"))) {
        const qsizetype comma = source.indexOf(QLatin1Char(','));
        if (comma < 0)
            return {};
        return QImage::fromData(QByteArray::fromBase64(source.mid(comma + 1).toLatin1()));
    }
    const QUrl url(source);
    return QImage(url.isLocalFile() ? url.toLocalFile() : source);
}

QColor ImageTools::dominantColorOf(const QImage &image, const QColor &fallback)
{
    if (image.isNull())
        return fallback;
    const QImage small = image.scaled(32, 32, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                             .convertToFormat(QImage::Format_ARGB32);
    // 24 hue buckets weighted by saturation * value: vivid colours win.
    struct Bucket {
        double weight = 0, r = 0, g = 0, b = 0;
    };
    std::array<Bucket, 24> buckets{};
    double ar = 0, ag = 0, ab = 0;
    int n = 0;
    for (int y = 0; y < small.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(small.constScanLine(y));
        for (int x = 0; x < small.width(); ++x) {
            const QColor c = QColor::fromRgba(line[x]);
            if (c.alpha() < 128)
                continue;
            ar += c.redF(), ag += c.greenF(), ab += c.blueF(), ++n;
            const double s = c.hsvSaturationF(), v = c.valueF();
            if (s < 0.25 || v < 0.25)
                continue;
            Bucket &bk = buckets[size_t(qMax(0, c.hsvHue()) * 24 / 360) % 24];
            const double w = s * v;
            bk.weight += w, bk.r += c.redF() * w, bk.g += c.greenF() * w, bk.b += c.blueF() * w;
        }
    }
    const Bucket *best = nullptr;
    for (const Bucket &bk : buckets)
        if (bk.weight > 0 && (!best || bk.weight > best->weight))
            best = &bk;
    if (best && best->weight > 1.5)
        return QColor::fromRgbF(float(best->r / best->weight), float(best->g / best->weight), float(best->b / best->weight));
    if (n == 0)
        return fallback;
    return QColor::fromRgbF(float(ar / n), float(ag / n), float(ab / n));
}

QColor ImageTools::dominantColor(const QString &source, const QColor &fallback) const
{
    return dominantColorOf(load(source), fallback);
}

} // namespace astra::qml
