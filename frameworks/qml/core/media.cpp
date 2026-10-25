// SPDX-License-Identifier: Apache-2.0
#include "media.h"
#include "imagetools.h"

#include <astra/client.h>

#include <QBuffer>
#include <QImage>
#include <QJsonObject>
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
    QImage img;
    if (image.canConvert<QImage>())
        img = image.value<QImage>();
    else
        img = ImageTools::load(image.toString());
    if (img.isNull()) {
        m_artwork.clear();
    } else {
        img = img.scaled(384, 384, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        img.save(&buffer, "PNG");
        m_artwork = QStringLiteral("data:image/png;base64,") + QString::fromLatin1(png.toBase64());
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
