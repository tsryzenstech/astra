# AnimationEngine

Fluid motion is the top priority of astraOS, so it has its own system
component: `frameworks/animation`, exposed to QML as `Astra.Animation` and
used by SysBoard and every app.

## Springs, not durations

Motion is described by two numbers designers can reason about:

- `response` – how quickly the value reaches its target (the period of the
  undamped oscillation, in seconds)
- `dampingFraction` – `1.0` arrives without overshoot, below `1.0` bounces,
  above `1.0` is sluggish

The solver (`spring.cpp`) is the closed-form solution of a damped harmonic
oscillator, so it is exact at any frame rate and can be sampled at any time.

## Spring

```qml
import Astra.Animation

Spring {
    id: openness
    to: drawer.open ? 1 : 0
    response: 0.4
    dampingFraction: 0.8
}
Item { y: -200 * (1 - openness.value) }
```

Changing `to` while the spring is moving keeps position **and velocity**
continuous: interrupting an animation never jumps. Gestures write `value`
directly while the finger is down and hand over the finger's speed when it
lifts:

```qml
VelocityTracker { id: tracker }
MouseArea {
    onPressed: (m) => { tracker.reset(); tracker.addPoint(m.x, m.y) }
    onPositionChanged: (m) => { tracker.addPoint(m.x, m.y); openness.value = progressFor(m) }
    onReleased: openness.animateTo(shouldOpen ? 1 : 0, tracker.velocity().y / distance)
}
```

## SpringNumberAnimation

A `NumberAnimation` whose easing curve is a spring, for `Behavior`s and
`Transition`s:

```qml
Behavior on x { SpringNumberAnimation { preset: Motion.bouncy } }
```

## Motion tokens

| Token | response / damping | Used for |
|---|---|---|
| `Motion.snappy` | 0.30 / 0.86 | presses, toggles, icon rearranging |
| `Motion.smooth` | 0.45 / 1.00 | page transitions |
| `Motion.bouncy` | 0.50 / 0.68 | Control/Notification Center components |
| `Motion.gentle` | 0.65 / 0.90 | large surfaces |
| `Motion.launch` | 0.42 / 0.84 | app open/close |
| `Motion.stagger` | 28 ms | delay between items entering together |

Helpers: `Motion.rubberband(offset, dimension)` (over-scroll resistance),
`Motion.project(velocity)` (where a flick comes to rest),
`Motion.curve()` / `Motion.duration()` (spring → easing curve).

`ASTRA_ANIMATION_SCALE` scales every animation system-wide (`0` disables
motion, e.g. for accessibility or tests).
