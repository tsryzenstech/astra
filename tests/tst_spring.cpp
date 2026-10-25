// SPDX-License-Identifier: Apache-2.0
#include "spring.h"

#include <QTest>

#include <algorithm>
#include <cmath>

using namespace astra::animation;

class TestSpring : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void startsAtDisplacement()
    {
        const SpringSolver s({0.4, 0.8}, -1.0, 0.0);
        QCOMPARE(s.displacement(0), -1.0);
        QVERIFY(std::abs(s.velocity(0)) < 1e-9);
    }

    void settles_data()
    {
        QTest::addColumn<double>("damping");
        QTest::newRow("bouncy") << 0.5;
        QTest::newRow("critical") << 1.0;
        QTest::newRow("overdamped") << 1.6;
    }
    void settles()
    {
        QFETCH(double, damping);
        const SpringParams p{0.45, damping};
        const double t = SpringSolver::settleTime(p);
        QVERIFY(t > 0 && t < 5);
        const SpringSolver s(p, -1.0, 0.0);
        QVERIFY(s.isSettled(t + 0.05, 0.001));
    }

    void criticalDoesNotOvershoot()
    {
        const SpringSolver s({0.45, 1.0}, -1.0, 0.0);
        for (double t = 0; t < 3; t += 0.01)
            QVERIFY(s.displacement(t) <= 1e-9);
    }

    void underdampedOvershoots()
    {
        const SpringSolver s({0.45, 0.5}, -1.0, 0.0);
        double maxPos = -1;
        for (double t = 0; t < 3; t += 0.005)
            maxPos = std::max(maxPos, s.displacement(t));
        QVERIFY(maxPos > 0.05);
    }

    void velocityMatchesDerivative()
    {
        for (double z : {0.4, 1.0, 1.5}) {
            const SpringSolver s({0.5, z}, -1.0, 3.0);
            for (double t = 0.01; t < 1.0; t += 0.07) {
                const double h = 1e-6;
                const double numeric = (s.displacement(t + h) - s.displacement(t - h)) / (2 * h);
                QVERIFY2(std::abs(numeric - s.velocity(t)) < 1e-4, qPrintable(QString::number(z)));
            }
        }
    }
};

QTEST_APPLESS_MAIN(TestSpring)
#include "tst_spring.moc"
