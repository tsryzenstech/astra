// SPDX-License-Identifier: Apache-2.0
#include "spring.h"

#include <algorithm>
#include <cmath>

namespace astra::animation {

SpringSolver::SpringSolver(const SpringParams &params, double displacement, double velocity)
    : m_omega(2.0 * M_PI / std::max(params.response, 0.01))
    , m_zeta(std::max(params.dampingFraction, 0.0))
    , m_x0(displacement)
    , m_v0(velocity)
{
}

double SpringSolver::displacement(double t) const
{
    const double w = m_omega, z = m_zeta, x0 = m_x0, v0 = m_v0;
    if (z < 1.0) {
        const double wd = w * std::sqrt(1.0 - z * z);
        return std::exp(-z * w * t) * (x0 * std::cos(wd * t) + (v0 + z * w * x0) / wd * std::sin(wd * t));
    }
    if (z == 1.0)
        return std::exp(-w * t) * (x0 + (v0 + w * x0) * t);
    const double s = std::sqrt(z * z - 1.0);
    const double r1 = -w * (z - s), r2 = -w * (z + s);
    const double c1 = (v0 - r2 * x0) / (r1 - r2);
    const double c2 = x0 - c1;
    return c1 * std::exp(r1 * t) + c2 * std::exp(r2 * t);
}

double SpringSolver::velocity(double t) const
{
    const double w = m_omega, z = m_zeta, x0 = m_x0, v0 = m_v0;
    if (z < 1.0) {
        const double wd = w * std::sqrt(1.0 - z * z);
        const double a = x0, b = (v0 + z * w * x0) / wd;
        const double e = std::exp(-z * w * t), c = std::cos(wd * t), s = std::sin(wd * t);
        return e * ((b * wd - z * w * a) * c - (a * wd + z * w * b) * s);
    }
    if (z == 1.0) {
        const double b = v0 + w * x0;
        return std::exp(-w * t) * (b - w * (x0 + b * t));
    }
    const double s = std::sqrt(z * z - 1.0);
    const double r1 = -w * (z - s), r2 = -w * (z + s);
    const double c1 = (v0 - r2 * x0) / (r1 - r2);
    const double c2 = x0 - c1;
    return c1 * r1 * std::exp(r1 * t) + c2 * r2 * std::exp(r2 * t);
}

bool SpringSolver::isSettled(double t, double epsilon) const
{
    // Velocity is compared per frame (1/60 s) so the threshold is unit independent.
    return std::abs(displacement(t)) < epsilon && std::abs(velocity(t)) / 60.0 < epsilon;
}

double SpringSolver::settleTime(const SpringParams &params, double epsilon)
{
    const SpringSolver unit(params, -1.0, 0.0);
    double settled = 0.0;
    // Find the last time the motion leaves the epsilon band.
    for (double t = 0.0; t < 10.0; t += 1.0 / 240.0)
        if (!unit.isSettled(t, epsilon))
            settled = t;
    return settled + 1.0 / 240.0;
}

} // namespace astra::animation
