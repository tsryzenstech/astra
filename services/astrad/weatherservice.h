// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "server.h"

#include <QTimer>

class QNetworkAccessManager;

namespace astrad {

class SettingsService;

// Current weather for the configured city (Open-Meteo, no API key).
// Feeds the home screen greeting and the Weather widgets.
class WeatherService : public Service
{
    Q_OBJECT
public:
    WeatherService(Server *server, SettingsService *settings, QObject *parent = nullptr);

    QJsonValue handle(const QString &call, const QJsonObject &params, const Caller &caller) override;

    // WMO weather interpretation code -> astra condition name.
    static QString condition(int code, bool isDay);

private:
    void refresh();

    Server *m_server;
    SettingsService *m_settings;
    QNetworkAccessManager *m_network;
    QTimer m_timer;
    QString m_cachePath;
    QJsonObject m_current;
};

} // namespace astrad
