// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QColor>
#include <QImage>
#include <QObject>
#include <QtQml/qqmlregistration.h>

namespace astra::qml {

// Image helpers for the system UI (singleton "ImageTools").
class ImageTools : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit ImageTools(QObject *parent = nullptr);

    // Most prominent vivid colour of an image (file path, file:// or data: URL).
    Q_INVOKABLE QColor dominantColor(const QString &source, const QColor &fallback = QColor()) const;

    static QImage load(const QString &source);
    static QColor dominantColorOf(const QImage &image, const QColor &fallback = QColor());
};

} // namespace astra::qml
