// SPDX-License-Identifier: Apache-2.0
#include "velocitytracker.h"

namespace astra::animation {

namespace {
constexpr qint64 kWindowMs = 80;
}

VelocityTracker::VelocityTracker(QObject *parent)
    : QObject(parent)
{
    m_clock.start();
}

void VelocityTracker::reset()
{
    m_samples.clear();
}

void VelocityTracker::addPoint(qreal x, qreal y)
{
    const qint64 now = m_clock.elapsed();
    m_samples.append({now, QPointF(x, y)});
    while (m_samples.size() > 2 && now - m_samples.first().t > kWindowMs)
        m_samples.removeFirst();
}

QPointF VelocityTracker::velocity() const
{
    if (m_samples.size() < 2)
        return {};
    const Sample &last = m_samples.last();
    // A finger that stopped before lifting should not fling.
    if (m_clock.elapsed() - last.t > kWindowMs)
        return {};
    const Sample &first = m_samples.first();
    const qint64 dt = last.t - first.t;
    if (dt <= 0)
        return {};
    return (last.p - first.p) * (1000.0 / double(dt));
}

} // namespace astra::animation
