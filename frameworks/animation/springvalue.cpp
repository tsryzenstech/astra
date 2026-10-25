// SPDX-License-Identifier: Apache-2.0
#include "springvalue.h"
#include "motion.h"

#include <cmath>

namespace astra::animation {

SpringDriver::SpringDriver(SpringValue *owner)
    : m_owner(owner)
{
}

void SpringDriver::updateCurrentTime(int currentTime)
{
    m_owner->tick(currentTime);
}

SpringValue::SpringValue(QObject *parent)
    : QObject(parent)
    , m_driver(this)
{
    connect(&m_driver, &QAbstractAnimation::stateChanged, this, &SpringValue::runningChanged);
}

SpringValue::~SpringValue()
{
    m_driver.stop();
}

bool SpringValue::running() const
{
    return m_driver.state() == QAbstractAnimation::Running;
}

void SpringValue::componentComplete()
{
    m_complete = true;
    // A spring starts at rest on its target unless a start value was given.
    if (!m_valueAssigned) {
        m_value = m_to;
        Q_EMIT valueChanged();
    } else if (!qFuzzyCompare(m_value, m_to)) {
        restart(0);
    }
}

void SpringValue::setTo(qreal to)
{
    if (qFuzzyCompare(m_to, to))
        return;
    m_to = to;
    Q_EMIT toChanged();
    if (m_complete)
        restart(m_velocity);
}

void SpringValue::setValue(qreal value)
{
    m_valueAssigned = true;
    m_driver.stop();
    m_solver.reset();
    if (qFuzzyCompare(m_value, value) && m_velocity == 0)
        return;
    m_value = value;
    m_velocity = 0;
    Q_EMIT valueChanged();
}

void SpringValue::setResponse(qreal r)
{
    if (qFuzzyCompare(m_params.response, r))
        return;
    m_params.response = r;
    Q_EMIT paramsChanged();
}

void SpringValue::setDampingFraction(qreal d)
{
    if (qFuzzyCompare(m_params.dampingFraction, d))
        return;
    m_params.dampingFraction = d;
    Q_EMIT paramsChanged();
}

void SpringValue::setEpsilon(qreal e)
{
    if (qFuzzyCompare(m_epsilon, e))
        return;
    m_epsilon = e;
    Q_EMIT paramsChanged();
}

void SpringValue::snap(qreal value)
{
    m_driver.stop();
    m_solver.reset();
    const bool toChange = !qFuzzyCompare(m_to, value);
    m_to = value;
    m_value = value;
    m_velocity = 0;
    if (toChange)
        Q_EMIT toChanged();
    Q_EMIT valueChanged();
}

void SpringValue::animateTo(qreal target, qreal initialVelocity)
{
    const bool toChange = !qFuzzyCompare(m_to, target);
    m_to = target;
    if (toChange)
        Q_EMIT toChanged();
    restart(std::isnan(initialVelocity) ? m_velocity : initialVelocity);
}

void SpringValue::restart(qreal velocity)
{
    const qreal scale = Motion::globalDurationScale();
    if (scale <= 0) { // animations disabled
        m_driver.stop();
        m_value = m_to;
        m_velocity = 0;
        Q_EMIT valueChanged();
        Q_EMIT settled();
        return;
    }
    m_solver = std::make_unique<SpringSolver>(m_params, m_value - m_to, velocity);
    m_driver.stop();
    m_driver.start();
}

void SpringValue::tick(int ms)
{
    if (!m_solver)
        return;
    // Normalise the displacement so epsilon works for both 0..1 and pixel ranges.
    const double t = ms / 1000.0 / Motion::globalDurationScale();
    const double d = m_solver->displacement(t);
    m_value = m_to + d;
    m_velocity = m_solver->velocity(t);

    const double range = std::max(1.0, std::abs(m_to));
    if (std::abs(d) / range < m_epsilon && std::abs(m_velocity) / 60.0 / range < m_epsilon) {
        m_value = m_to;
        m_velocity = 0;
        m_solver.reset();
        m_driver.stop();
        Q_EMIT valueChanged();
        Q_EMIT settled();
        return;
    }
    Q_EMIT valueChanged();
}

} // namespace astra::animation
