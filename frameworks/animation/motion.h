// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <QObject>
#include <QPointF>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

namespace astra::animation {

// System wide motion tokens. Everything that moves in astraOS goes through
// these presets, so the feel of the system can be tuned in one place and the
// whole system honours the global animation scale (0 disables motion).
class Motion : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(qreal durationScale READ durationScale WRITE setDurationScale NOTIFY durationScaleChanged)
    Q_PROPERTY(QVariantMap snappy READ snappy CONSTANT)
    Q_PROPERTY(QVariantMap smooth READ smooth CONSTANT)
    Q_PROPERTY(QVariantMap bouncy READ bouncy CONSTANT)
    Q_PROPERTY(QVariantMap gentle READ gentle CONSTANT)
    Q_PROPERTY(QVariantMap launch READ launch CONSTANT)
    Q_PROPERTY(int stagger READ stagger NOTIFY durationScaleChanged)
    Q_PROPERTY(int fast READ fast NOTIFY durationScaleChanged)
    Q_PROPERTY(int normal READ normal NOTIFY durationScaleChanged)

public:
    explicit Motion(QObject *parent = nullptr);
    ~Motion() override;

    static qreal globalDurationScale();
    // The shell changes the scale live (Developer Options); apps read it
    // from ASTRA_ANIMATION_SCALE when they start.
    static void setGlobalDurationScale(qreal scale);

    qreal durationScale() const { return globalDurationScale(); }
    void setDurationScale(qreal scale) { setGlobalDurationScale(scale); }
    QVariantMap snappy() const { return preset(0.30, 0.86); }
    QVariantMap smooth() const { return preset(0.45, 1.00); }
    QVariantMap bouncy() const { return preset(0.50, 0.68); }
    QVariantMap gentle() const { return preset(0.65, 0.90); }
    QVariantMap launch() const { return preset(0.42, 0.84); }
    int stagger() const { return int(28 * globalDurationScale()); }
    int fast() const { return int(160 * globalDurationScale()); }
    int normal() const { return int(260 * globalDurationScale()); }

    // Easing curve (for Easing.BezierSpline) that reproduces a spring
    // starting at rest, so springs can drive Behaviors and Transitions.
    Q_INVOKABLE QList<qreal> curve(qreal response, qreal dampingFraction) const;
    // Duration in ms of the spring above, scaled by the global animation scale.
    Q_INVOKABLE int duration(qreal response, qreal dampingFraction) const;

    // iOS style rubber banding for over-scroll: offset beyond the edge -> visual offset.
    Q_INVOKABLE qreal rubberband(qreal offset, qreal dimension, qreal coefficient = 0.55) const;
    // Where a flick with the given velocity (px/s) would come to rest.
    Q_INVOKABLE qreal project(qreal velocity, qreal decelerationRate = 0.998) const;

Q_SIGNALS:
    void durationScaleChanged();

private:
    static QVariantMap preset(qreal response, qreal damping);
};

} // namespace astra::animation
