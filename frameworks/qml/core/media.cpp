// SPDX-License-Identifier: Apache-2.0
#include "media.h"
#include "imagetools.h"

#include <astra/client.h>

#include <QBuffer>
#include <QCoreApplication>
#include <QImage>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QUrl>

namespace astra::qml {

MediaController::MediaController(QObject *parent)
    : QObject(parent)
{
    Client *c = Client::instance();
    c->subscribe({QStringLiteral("media")});
    auto fetch = [this] {
        Client::instance()->call(QStringLiteral("media.current"), {},
                                 [this](const QJsonValue &r, const QString &) { update(r); });
    };
    connect(c, &Client::connectedChanged, this, [fetch](bool up) {
        if (up)
            fetch();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name == QLatin1String("media.changed"))
            update(data);
    });
    if (c->isConnected())
        fetch();
}

void MediaController::update(const QJsonValue &session)
{
    m_session = session.toObject().toVariantMap();
    if (!m_session.isEmpty())
        m_session.insert(QStringLiteral("iconUrl"), QUrl::fromLocalFile(m_session.value(QStringLiteral("icon")).toString()));
    Q_EMIT sessionChanged();
}

void MediaController::command(const QString &action, qreal position)
{
    QJsonObject params{{QStringLiteral("action"), action}};
    if (position >= 0)
        params.insert(QStringLiteral("position"), position);
    Client::instance()->call(QStringLiteral("media.command"), params);
}

MediaSession::MediaSession(QObject *parent)
    : QObject(parent)
{
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(60);
    connect(&m_debounce, &QTimer::timeout, this, &MediaSession::publish);
    connect(this, &MediaSession::changed, &m_debounce, qOverload<>(&QTimer::start));

    Client *c = Client::instance();
    connect(c, &Client::connectedChanged, this, [this](bool up) {
        if (up)
            m_debounce.start();
    });
    connect(c, &Client::event, this, [this](const QString &name, const QJsonValue &data) {
        if (name != QLatin1String("media.command"))
            return;
        const QJsonObject o = data.toObject();
        Q_EMIT command(o.value(QLatin1String("action")).toString(), o.value(QLatin1String("position")).toDouble(-1));
    });
}

MediaSession::~MediaSession()
{
    Client::instance()->call(QStringLiteral("media.release"));
}

void MediaSession::setArtworkImage(const QVariant &image)
{
    const int request = ++m_artworkRequest;
    if (image.metaType().id() == QMetaType::QImage) {
        applyArtwork(image.value<QImage>());
        return;
    }
    const QString source = image.toString();
    const QUrl url(source);
    if (url.scheme() == QLatin1String("http") || url.scheme() == QLatin1String("https")) {
        static QNetworkAccessManager *network = new QNetworkAccessManager(qApp);
        QNetworkRequest r(url);
        r.setTransferTimeout(15000);
        QNetworkReply *reply = network->get(r);
        QPointer<MediaSession> self(this);
        connect(reply, &QNetworkReply::finished, reply, [self, reply, request] {
            reply->deleteLater();
            // Only the latest cover counts: songs change faster than downloads.
            if (!self || request != self->m_artworkRequest)
                return;
            self->applyArtwork(reply->error() == QNetworkReply::NoError ? QImage::fromData(reply->readAll()) : QImage());
        });
        return;
    }
    applyArtwork(source.isEmpty() ? QImage() : ImageTools::load(source));
}

// Rows that are black from edge to edge, at the top and the bottom.
static QImage trimBars(const QImage &src)
{
    const QImage img = src.convertToFormat(QImage::Format_RGB32);
    auto dark = [&img](int y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); x += 3)
            if (qGray(line[x]) > 24)
                return false;
        return true;
    };
    int top = 0, bottom = img.height() - 1;
    while (top < img.height() / 4 && dark(top))
        ++top;
    while (bottom > img.height() * 3 / 4 && dark(bottom))
        --bottom;
    if (top == 0 && bottom == img.height() - 1)
        return src;
    return img.copy(0, top, img.width(), bottom - top + 1);
}

void MediaSession::applyArtwork(QImage img)
{
    if (img.isNull()) {
        m_artwork.clear();
    } else {
        // Video thumbnails: black bars above and below a 16:9 frame, which
        // holds a square cover in the middle.
        if (img.width() > img.height() * 1.05)
            img = trimBars(img);
        if (img.width() > img.height() * 1.1) {
            const int side = img.height();
            img = img.copy((img.width() - side) / 2, 0, side, side);
        }
        img = img.scaled(384, 384, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        // JPEG: a photo-like cover as PNG can pass astrad's 512 KB limit.
        img.convertToFormat(QImage::Format_RGB32).save(&buffer, "JPG", 90);
        m_artwork = QStringLiteral("data:image/jpeg;base64,") + QString::fromLatin1(png.toBase64());
        m_accent = ImageTools::dominantColorOf(img);
    }
    Q_EMIT changed();
}

void MediaSession::publish()
{
    if (!m_active || m_title.isEmpty()) {
        Client::instance()->call(QStringLiteral("media.release"));
        return;
    }
    Client::instance()->call(QStringLiteral("media.publish"),
                             {
                                 {QStringLiteral("title"), m_title},
                                 {QStringLiteral("artist"), m_artist},
                                 {QStringLiteral("album"), m_album},
                                 {QStringLiteral("artwork"), m_artwork},
                                 {QStringLiteral("accent"), m_accent.isValid() ? m_accent.name() : QString()},
                                 {QStringLiteral("duration"), m_duration},
                                 {QStringLiteral("position"), m_position},
                                 {QStringLiteral("playing"), m_playing},
                             });
}

} // namespace astra::qml
