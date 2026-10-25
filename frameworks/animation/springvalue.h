// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "spring.h"

#include <QAbstractAnimation>
#include <QObject>
#include <QQmlParserStatus>
#include <QtQml/qqmlregistration.h>

#include <memory>

namespace astra::animation {

class SpringValue;

class SpringDriver : public QAbstractAnimation
{
public:
    explicit SpringDriver(SpringValue *owner);
    int duration() const override { return -1; }

protected:
    void updateCurrentTime(int currentTime) override;

private:
    SpringValue *m_owner;
};

// An interruptible, velocity preserving spring.
//
//   Spring { id: openness; to: drawer.open ? 1 : 0; response: 0.4; dampingFraction: 0.8 }
//   Item { y: -200 * (1 - openness.value) }
//
// Gestures write `value` directly while tracking a finger, then hand the
// release velocity to animateTo() so the motion continues seamlessly.
class SpringValue : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_NAMED_ELEMENT(Spring)

    Q_PROPERTY(qreal to READ to WRITE setTo NOTIFY toChanged)
    Q_PROPERTY(qreal value READ value WRITE setValue NOTIFY valueChanged)
    Q_PROPERTY(qreal velocity READ velocity NOTIFY valueChanged)
    Q_PROPERTY(qreal response READ response WRITE setResponse NOTIFY paramsChanged)
    Q_PROPERTY(qreal dampingFraction READ dampingFraction WRITE setDampingFraction NOTIFY paramsChanged)
    Q_PROPERTY(qreal epsilon READ epsilon WRITE setEpsilon NOTIFY paramsChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)

public:
    explicit SpringValue(QObject *parent = nullptr);
    ~SpringValue() override;

    qreal to() const { return m_to; }
    void setTo(qreal to);
    qreal value() const { return m_value; }
    void setValue(qreal value);
    qreal velocity() const { return m_velocity; }
    qreal response() const { return m_params.response; }
    void setResponse(qreal r);
    qreal dampingFraction() const { return m_params.dampingFraction; }
    void setDampingFraction(qreal d);
    qreal epsilon() const { return m_epsilon; }
    void setEpsilon(qreal e);
    bool running() const;

    // Jumps to a value without animating.
    Q_INVOKABLE void snap(qreal value);
    // Animates to target starting with the given velocity (units/s).
    Q_INVOKABLE void animateTo(qreal target, qreal initialVelocity);

    void classBegin() override {}
    void componentComplete() override;

Q_SIGNALS:
    void toChanged();
    void valueChanged();
    void paramsChanged();
    void runningChanged();
    void settled();

private:
    friend class SpringDriver;
    void restart(qreal velocity);
    void tick(int ms);

    SpringParams m_params;
    qreal m_to = 0;
    qreal m_value = 0;
    qreal m_velocity = 0;
    qreal m_epsilon = 0.001;
    bool m_complete = false;
    bool m_valueAssigned = false;
    std::unique_ptr<SpringSolver> m_solver;
    SpringDriver m_driver;
};

} // namespace astra::animation
