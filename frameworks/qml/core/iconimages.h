// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QColor>
#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class QJSEngine;
class QQmlEngine;

namespace astra::qml {

// Icons drawn once, into an ordinary image: rounded to the icon shape, or tinted.
// Nothing to render later, so nothing to go missing: with a mask effect per icon, a
// different icon stayed blank on each start of the phone, and each one cost two
// offscreen layers for as long as it was on screen.
class IconImages : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    static IconImages *create(QQmlEngine *engine, QJSEngine *);

    // Sources for an Image; set its sourceSize to the pixels you need.
    Q_INVOKABLE QUrl rounded(const QUrl &source, qreal radiusRatio) const;
    Q_INVOKABLE QUrl tinted(const QUrl &source, const QColor &color) const;

private:
    explicit IconImages(QObject *parent = nullptr);
};

} // namespace astra::qml
