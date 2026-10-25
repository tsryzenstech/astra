// SPDX-License-Identifier: Apache-2.0
#pragma once

// Closed-form damped harmonic oscillator, the core of the AnimationEngine.
//
// Springs are described the way designers think about them:
//   response        - period of the undamped oscillation, in seconds
//                     (how quickly the value gets to the target)
//   dampingFraction - 1.0 is critically damped (no overshoot),
//                     < 1.0 bounces, > 1.0 is sluggish
//
// The solution is analytic, so it is frame-rate independent and can be
// evaluated at any time t. Retargeting keeps position and velocity
// continuous, which is what makes interrupted animations feel "buttery".

namespace astra::animation {

struct SpringParams {
    double response = 0.45;
    double dampingFraction = 0.86;
};

class SpringSolver
{
public:
    // displacement: start - target; velocity in units per second.
    SpringSolver(const SpringParams &params, double displacement, double velocity);

    double displacement(double t) const; // value(t) - target
    double velocity(double t) const;
    bool isSettled(double t, double epsilon) const;

    // Time after which the motion stays within epsilon of the target.
    static double settleTime(const SpringParams &params, double epsilon = 0.001);

private:
    double m_omega;   // natural angular frequency
    double m_zeta;    // damping ratio
    double m_x0;
    double m_v0;
};

} // namespace astra::animation
