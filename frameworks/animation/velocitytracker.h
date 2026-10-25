// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QPointF>
#include <QVector>
#include <QtQml/qqmlregistration.h>

namespace astra::animation {

// Estimates pointer velocity (px/s) from recent samples, so gesture driven
// springs can continue with the exact speed of the finger on release.
class VelocityTracker : public QObject
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit VelocityTracker(QObject *parent = nullptr);

    Q_INVOKABLE void reset();
    Q_INVOKABLE void addPoint(qreal x, qreal y);
    Q_INVOKABLE QPointF velocity() const;

private:
    struct Sample {
        qint64 t;
        QPointF p;
    };
    QElapsedTimer m_clock;
    QVector<Sample> m_samples;
};

} // namespace astra::animation
