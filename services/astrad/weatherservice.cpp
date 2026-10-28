// SPDX-License-Identifier: Apache-2.0
#include "weatherservice.h"
#include "jsonstore.h"
#include "settingsservice.h"

#include <astra/paths.h>
#include <astra/protocol.h>

#include <QDateTime>
#include <QJsonArray>
#include <QLoggingCategory>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QUrlQuery>

Q_LOGGING_CATEGORY(lcWeather, "astrad.weather")

namespace astrad {

using namespace astra;

WeatherService::WeatherService(Server *server, SettingsService *settings, QObject *parent)
    : Service(parent)
    , m_server(server)
    , m_settings(settings)
    , m_network(new QNetworkAccessManager(this))
    , m_cachePath(Paths::dataSystem() + QStringLiteral("/weather.json"))
{
    m_current = loadJson(m_cachePath);
    m_timer.setInterval(30 * 60 * 1000);
    connect(&m_timer, &QTimer::timeout, this, &WeatherService::refresh);
    m_timer.start();
    connect(settings, &SettingsService::changed, this, [this](const QString &key) {
        if (key.startsWith(QLatin1String("weather.")))
            refresh();
    });
    QTimer::singleShot(2000, this, &WeatherService::refresh);
}

QString WeatherService::condition(int code, bool isDay)
{
    if (code <= 1)
        return isDay ? QStringLiteral("sunny") : QStringLiteral("clear");
    if (code == 2)
        return isDay ? QStringLiteral("partly-cloudy") : QStringLiteral("clear");
    if (code == 3)
        return QStringLiteral("cloudy");
    if (code == 45 || code == 48)
        return QStringLiteral("foggy");
    if ((code >= 71 && code <= 77) || code == 85 || code == 86)
        return QStringLiteral("snowy");
    if (code >= 95)
        return QStringLiteral("stormy");
    return QStringLiteral("rainy");
}

void WeatherService::refresh()
{
    if (!m_settings->value(QStringLiteral("weather.enabled")).toBool(true))
        return;
    QUrl url(QStringLiteral("https://api.open-meteo.com/v1/forecast"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("latitude"), QString::number(m_settings->value(QStringLiteral("weather.latitude")).toDouble(45.4642)));
    q.addQueryItem(QStringLiteral("longitude"), QString::number(m_settings->value(QStringLiteral("weather.longitude")).toDouble(9.19)));
    q.addQueryItem(QStringLiteral("current"),
                   QStringLiteral("temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"));
    q.addQueryItem(QStringLiteral("hourly"), QStringLiteral("temperature_2m,weather_code,is_day"));
    q.addQueryItem(QStringLiteral("daily"),
                   QStringLiteral("temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset,uv_index_max,precipitation_probability_max"));
    q.addQueryItem(QStringLiteral("timezone"), QStringLiteral("auto"));
    q.addQueryItem(QStringLiteral("forecast_days"), QStringLiteral("7"));
    q.addQueryItem(QStringLiteral("forecast_hours"), QStringLiteral("24"));
    if (m_settings->value(QStringLiteral("weather.units")).toString() == QLatin1String("fahrenheit"))
        q.addQueryItem(QStringLiteral("temperature_unit"), QStringLiteral("fahrenheit"));
    url.setQuery(q);

    QNetworkRequest request(url);
    request.setTransferTimeout(15000);
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            qCInfo(lcWeather) << "update failed:" << reply->errorString();
            return;
        }
        const QJsonObject doc = QJsonDocument::fromJson(reply->readAll()).object();
        const QJsonObject cur = doc.value(QLatin1String("current")).toObject();
        const QJsonObject daily = doc.value(QLatin1String("daily")).toObject();
        const QJsonObject hourly = doc.value(QLatin1String("hourly")).toObject();
        const int code = cur.value(QLatin1String("weather_code")).toInt();
        const bool day = cur.value(QLatin1String("is_day")).toInt(1) == 1;
        auto at = [](const QJsonObject &o, const char *key, int i) { return o.value(QLatin1String(key)).toArray().at(i); };

        QJsonArray hours;
        const QJsonArray hourTimes = hourly.value(QLatin1String("time")).toArray();
        for (int i = 0; i < hourTimes.size(); ++i)
            hours.append(QJsonObject{
                {QStringLiteral("time"), hourTimes.at(i)},
                {QStringLiteral("temperature"), qRound(at(hourly, "temperature_2m", i).toDouble())},
                {QStringLiteral("condition"), condition(at(hourly, "weather_code", i).toInt(), at(hourly, "is_day", i).toInt(1) == 1)},
            });
        QJsonArray days;
        const QJsonArray dayTimes = daily.value(QLatin1String("time")).toArray();
        for (int i = 0; i < dayTimes.size(); ++i)
            days.append(QJsonObject{
                {QStringLiteral("date"), dayTimes.at(i)},
                {QStringLiteral("min"), qRound(at(daily, "temperature_2m_min", i).toDouble())},
                {QStringLiteral("max"), qRound(at(daily, "temperature_2m_max", i).toDouble())},
                {QStringLiteral("condition"), condition(at(daily, "weather_code", i).toInt(), true)},
                {QStringLiteral("sunrise"), at(daily, "sunrise", i)},
                {QStringLiteral("sunset"), at(daily, "sunset", i)},
                {QStringLiteral("uv"), at(daily, "uv_index_max", i)},
                {QStringLiteral("precipitation"), at(daily, "precipitation_probability_max", i)},
            });
        m_current = {
            {QStringLiteral("city"), m_settings->value(QStringLiteral("weather.city")).toString()},
            {QStringLiteral("temperature"), qRound(cur.value(QLatin1String("temperature_2m")).toDouble())},
            {QStringLiteral("feelsLike"), qRound(cur.value(QLatin1String("apparent_temperature")).toDouble())},
            {QStringLiteral("humidity"), cur.value(QLatin1String("relative_humidity_2m")).toInt()},
            {QStringLiteral("wind"), qRound(cur.value(QLatin1String("wind_speed_10m")).toDouble())},
            {QStringLiteral("min"), days.isEmpty() ? 0 : days.at(0).toObject().value(QLatin1String("min")).toInt()},
            {QStringLiteral("max"), days.isEmpty() ? 0 : days.at(0).toObject().value(QLatin1String("max")).toInt()},
            {QStringLiteral("code"), code},
            {QStringLiteral("isDay"), day},
            {QStringLiteral("condition"), condition(code, day)},
            {QStringLiteral("units"), m_settings->value(QStringLiteral("weather.units")).toString(QStringLiteral("celsius"))},
            {QStringLiteral("hourly"), hours},
            {QStringLiteral("daily"), days},
            {QStringLiteral("updated"), double(QDateTime::currentMSecsSinceEpoch())},
        };
        saveJson(m_cachePath, m_current);
        m_server->broadcast(QStringLiteral("weather.changed"), m_current);
    });
}

QJsonValue WeatherService::handle(const QString &call, const QJsonObject &, const Caller &)
{
    if (call == QLatin1String("current"))
        return m_current.isEmpty() ? QJsonValue() : QJsonValue(m_current);
    if (call == QLatin1String("refresh")) {
        refresh();
        return true;
    }
    throw RpcError{protocol::MethodNotFound, call};
}

} // namespace astrad
