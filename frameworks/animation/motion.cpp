// SPDX-License-Identifier: Apache-2.0
#include "motion.h"
#include "spring.h"

#include <QHash>
#include <QMutex>

#include <cmath>

namespace astra::animation {

Motion::Motion(QObject *parent)
    : QObject(parent)
{
}

qreal Motion::globalDurationScale()
{
    static const qreal scale = [] {
        bool ok = false;
        const qreal v = qEnvironmentVariable("ASTRA_ANIMATION_SCALE").toDouble(&ok);
        return ok && v >= 0 ? v : 1.0;
    }();
    return scale;
}

QVariantMap Motion::preset(qreal response, qreal damping)
{
    return {{QStringLiteral("response"), response}, {QStringLiteral("dampingFraction"), damping}};
}

QList<qreal> Motion::curve(qreal response, qreal dampingFraction) const
{
    static QMutex lock;
    static QHash<QPair<qreal, qreal>, QList<qreal>> cache;
    QMutexLocker guard(&lock);
    const auto key = qMakePair(response, dampingFraction);
    if (auto it = cache.constFind(key); it != cache.constEnd())
        return *it;

    const SpringParams params{response, dampingFraction};
    const double total = SpringSolver::settleTime(params);
    const SpringSolver unit(params, -1.0, 0.0);

    // Hermite -> cubic Bezier conversion using the exact spring velocity.
    // QEasingCurve's BezierSpline holds at most 10 segments (more overflows
    // an internal buffer in Qt), so segment boundaries are packed towards the
    // start, where a spring moves (and bounces) the most.
    constexpr int segments = 10;
    auto boundary = [](int i) { return std::pow(double(i) / segments, 1.6); };
    QList<qreal> points;
    points.reserve(segments * 6);
    for (int i = 0; i < segments; ++i) {
        const double u0 = boundary(i), u1 = boundary(i + 1), du = u1 - u0;
        const bool last = i + 1 == segments;
        const double y0 = 1.0 + unit.displacement(u0 * total);
        const double y1 = last ? 1.0 : 1.0 + unit.displacement(u1 * total);
        const double m0 = unit.velocity(u0 * total) * total; // dy/du
        const double m1 = last ? 0.0 : unit.velocity(u1 * total) * total;
        points << u0 + du / 3 << y0 + m0 * du / 3 << u1 - du / 3 << y1 - m1 * du / 3 << (last ? 1.0 : u1) << y1;
    }
    cache.insert(key, points);
    return points;
}

int Motion::duration(qreal response, qreal dampingFraction) const
{
    return int(std::lround(SpringSolver::settleTime({response, dampingFraction}) * 1000.0 * globalDurationScale()));
}

qreal Motion::rubberband(qreal offset, qreal dimension, qreal coefficient) const
{
    if (dimension <= 0)
        return 0;
    const qreal sign = offset < 0 ? -1 : 1;
    const qreal x = std::abs(offset);
    return sign * (1.0 - 1.0 / (x * coefficient / dimension + 1.0)) * dimension;
}

qreal Motion::project(qreal velocity, qreal decelerationRate) const
{
    return velocity / 1000.0 * decelerationRate / (1.0 - decelerationRate);
}

} // namespace astra::animation
