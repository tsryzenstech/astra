// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QColor>
#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// The active media session as seen by the system UI (singleton).
class MediaController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantMap session READ session NOTIFY sessionChanged)
    Q_PROPERTY(bool active READ active NOTIFY sessionChanged)

public:
    explicit MediaController(QObject *parent = nullptr);

    QVariantMap session() const { return m_session; }
    bool active() const { return !m_session.isEmpty(); }

    Q_INVOKABLE void command(const QString &action, qreal position = -1);

Q_SIGNALS:
    void sessionChanged();

private:
    void update(const QJsonValue &session);
    QVariantMap m_session;
};

// Publishes what an app is playing:
//   MediaSession { title: player.title; artist: ...; playing: ...; onCommand: (a) => ... }
class MediaSession : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString title MEMBER m_title NOTIFY changed)
    Q_PROPERTY(QString artist MEMBER m_artist NOTIFY changed)
    Q_PROPERTY(QString album MEMBER m_album NOTIFY changed)
    Q_PROPERTY(QString artwork MEMBER m_artwork NOTIFY changed) // data: URL
    Q_PROPERTY(QColor accent MEMBER m_accent NOTIFY changed)
    Q_PROPERTY(qreal duration MEMBER m_duration NOTIFY changed)  // ms
    Q_PROPERTY(qreal position MEMBER m_position NOTIFY changed)  // ms
    Q_PROPERTY(bool playing MEMBER m_playing NOTIFY changed)
    Q_PROPERTY(bool active MEMBER m_active NOTIFY changed)

public:
    explicit MediaSession(QObject *parent = nullptr);
    ~MediaSession() override;

    // Accepts a QImage (e.g. MediaMetaData.CoverArtImage) or an image URL.
    Q_INVOKABLE void setArtworkImage(const QVariant &image);

Q_SIGNALS:
    void changed();
    void command(const QString &action, qreal position);

private:
    void publish();

    QString m_title, m_artist, m_album, m_artwork;
    QColor m_accent;
    qreal m_duration = 0, m_position = 0;
    bool m_playing = false;
    bool m_active = true;
    QTimer m_debounce;
};

} // namespace astra::qml
