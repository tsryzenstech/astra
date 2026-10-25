// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJSValue>
#include <QJsonValue>
#include <QObject>
#include <QUrl>
#include <QVariant>

namespace astra::qml {

// Calls a QML callback as cb(result, error) when it is callable.
void invokeCallback(QObject *context, const QJSValue &callback, const QJsonValue &result, const QString &error);

// Absolute filesystem path -> file:// URL for QML Image sources.
inline QUrl fileUrl(const QString &path)
{
    return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(path);
}

} // namespace astra::qml
