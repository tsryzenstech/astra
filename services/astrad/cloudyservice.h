// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QFile>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QTimer>

class QNetworkReply;

namespace astrad {

// Cloudy runs a small language model on the phone with llama.cpp's
// llama-server (/system/bin/llama-server), listening on 127.0.0.1:8742
// with an OpenAI compatible API. The model is downloaded once, when the
// user agrees, into /data/cloudy. The server stops when Cloudy hasn't been
// used for a while, to give the memory back.
//   cloudy.state -> {models: [{id, name, size, installed}], downloading, progress, running, ready, port, error}
//   cloudy.download {model}  cloudy.cancel  cloudy.remove {model}
//   cloudy.start {model}     cloudy.keepAlive  cloudy.stop        (Cloudy and the system)
class CloudyService : public Service
{
    Q_OBJECT
public:
    explicit CloudyService(Server *server, QObject *parent = nullptr);
    ~CloudyService() override;
    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

private:
    struct Model { QString id, name, file, url; qint64 size; };
    static const QList<Model> &models();
    const Model *model(const QString &id) const;
    QString pathOf(const Model &m) const;
    QJsonObject state() const;
    void announce();
    void download(const Model &m);
    void start(const Model &m);
    void stop();

    Server *m_server;
    QString m_dir;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QFile m_part;
    QString m_downloading;
    qint64 m_received = 0;
    qint64 m_total = 0;
    QString m_error;
    QProcess *m_process = nullptr;
    QString m_running;          // model id
    bool m_ready = false;       // the server answers
    QTimer m_idle;
    QTimer m_health;
    QTimer m_announce;
};

} // namespace astrad
