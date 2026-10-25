// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QFile>

namespace astrad {

// Atomic JSON persistence for /data/system state files.
inline QJsonObject loadJson(const QString &path)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object();
}

inline bool saveJson(const QString &path, const QJsonObject &object)
{
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly))
        return false;
    f.write(QJsonDocument(object).toJson(QJsonDocument::Indented));
    return f.commit();
}

} // namespace astrad
