# Grid Animation Spec

## Overview

A field of small dots arranged in a uniform grid, filling the screen. The animation supports multiple phases: an enter transition from a green keypad screen, a scanning state with a wandering search circle, a person-found state with avatar reveal, and a radial broadcast layout. A chromatic aberration effect adds visual richness near the search circle.

## Grid Layout

- **Dot shape**: Circle, ~1.5pt radius (3pt diameter)
- **Grid pattern**: Square grid with equal horizontal and vertical spacing (default 18pt)
- **Origin**: Grid is centered in the view (center-registered)
- **Coverage**: Grid fills the entire view bounds (default 20 columns x 35 rows)
- **Dot color**: White on black background
- **Base opacity**: 0.30 with per-dot random variation of +/-0.08

## Animation Phases

The animation progresses through six engine phases:

### 1. Idle

No animation. Dots are invisible (opacity 0). Background is green.

### 2. Formation (Enter Transition)

Transition from the green keypad screen to the black dot grid. Two simultaneous animations:

**Background**: Green overlay fades linearly to black over 1.2s. The linear ramp (not eased) ensures green lingers long enough for dots to be visible through it during transition.

**Dot reveal**: Center-outward perspective push with per-dot random stagger.

- Each dot has a random `zRainDelay` (0–1.0) assigned at setup
- Formation progress ramps 0→1 over 2.5s, mapped to 0→3 virtual time units
- Per-dot delayed start: `delayed = max(0, introTime - zRainDelay)`
- **Opacity**: Fades in fast via smoothstep over 0.5 virtual time units (~0.42s real)
- **Slide**: Dots start pushed outward from screen center proportional to their distance (up to 156pt for edge dots), slide inward via smoothstep over 1.3 virtual time units (~1.08s real)
- The combination creates dots appearing to zoom in from a perspective camera, with random per-dot timing for organic feel

**Easing**: Hermite smoothstep `3t² - 2t³` for both opacity and slide.

### 3. Scanning

Dots are stationary at their grid positions. The visual interest comes entirely from the **search circle** (wandering chaser).

**Search circle behavior**:
- Invisible circle that wanders the canvas using multi-sine Lissajous motion with 4 phase angles at different speeds
- Spring tracking (k=6.0, damping=0.82) toward the wander target for smooth organic motion
- Influence radius: 42pt (search radius 12pt × 3.5)

**Dot displacement near search circle**:
- Dots within the influence radius are pushed upward (negative Y) simulating Z-lift
- Push amount: `bell * 12pt` where bell is a smoothstep of proximity (0 at edge, 1 at center)
- **Opacity boost**: Dots near the circle brighten from 0.30 up to ~0.95 (`baseOpacity + scanElevation * 0.65`)
- **Size boost**: Dots grow up to 1.8× their normal radius (`1 + scanElevation * 0.8`)

**Chromatic aberration**: Dots affected by the search circle render with RGB channel separation:
- Three circles drawn with additive blending (R, G, B channels offset by `chaserIntensity * 0.3 * 3.5` points)
- Chaser intensity decays over ~1s after the search circle passes, creating a trailing effect
- Colors: R(1.0, 0.24, 0.24), G(0.24, 1.0, 0.24), B(0.24, 0.24, 1.0) — overlap produces white, fringes produce color

### 4. Person Found

The search circle freezes and an avatar appears at its position with a repulsion zone that pushes dots outward.

**Timeline**:
- 0ms: Search circle freezes at current position
- 200ms: Frozen circle starts growing + avatar begins fading in
- ~700ms: Circle at full size, avatar fully visible

**Frozen circle repulsion**:
- Circle radius grows via exponential lerp: `radius += (target - radius) * dt * 5` (target: 28pt)
- Opacity grows: `opacity += dt * 3`
- Influence zone: 84pt (target radius × 3)
- Inside the circle: strong outward push `(influenceR - dist) * 1.5`
- Outside the circle: cosine falloff `0.5 * (1 + cos(t * π)) * radius * 0.8`

**Avatar overlay**:
- Appears at the search circle's frozen position (screen coordinates)
- Fades in with easeInOut over 500ms, scales from 0.5× to 1.0×
- 56×56pt circle with person icon and name label below

### 5. Radial Transition (Broadcast Collapse)

Dots animate from grid positions to concentric ring positions around the screen center (for "Get Paid" mode). The transition features a "broadcast collapse" with per-particle scatter at the midpoint.

**Ring layout** (matches web prototype):
- Avatar radius: 28pt (just outside the 48px avatar)
- 9 visible rings, max visible radius 165pt
- Ring step: `(165 - 28) / 9 ≈ 15.2pt` per ring
- Dots distributed by ring circumference at 15pt arc-length spacing (no per-ring rotation offset)
- Overflow rings beyond the 9 visible rings: same spacing, fade over 3 rings `max(0, 1 - overflowRing / 3)`

**Collapse animation**:
- Duration: 2.0s
- Per-particle tiny delay: `zRainDelay × 0.05s`
- Easing: sine-based `(1 - cos(t × π)) × 0.5` (NOT spring)
- Per-particle scatter: random angle (0–2π) and magnitude (20–60pt), envelope `sin(t × π)` peaks at midpoint
- Overflow opacity: gradually applied during ease `1 - (1 - slotOpacity) × ease`

**Broadcast avatar**: 48×48px circular avatar at screen center, appears 2100ms after collapse starts with scale-in animation (0.5× → 1.0× over 500ms).

### 6. Radial Pulsing (Radiate)

Dots are **stationary** at their ring positions. No breathing displacement. Visual movement comes from opacity-only concentric waves.

**Base opacity**: 0.42 (higher than scanning's 0.30)

**Concentric opacity waves** (no displacement, no size change):
- Wave speed: 100pt/s, spawned every 2.0s
- Wave width: 50pt
- Multiple simultaneous waves (new one spawned while previous still fading)
- Each wave fades over 5s: `fade = max(0, 1 - waveAge / 5)`
- Dot opacity: `0.42 + waveAlphaBoost × 0.48` — waves brighten dots from 0.42 up to 0.90

**Pay flow** (triggered one-shot sequence in Get Paid mode):

Timeline:
1. **0ms**: Payer avatar (48px circle) slides up 30px and fades in at bottom of screen (400ms ease-in-out)
2. **250ms**: Pay wave fires (see below)
3. **1800ms**: iOS-style notification banner slides down from top: "Payment received — Elisa W. paid you $25." (spring animation, 400ms)
4. **3500ms**: Payer avatar fades out
5. **5800ms**: Notification auto-dismisses (slides back up)

**Pay wave effect** (dot-based animation, matches web):
- Traveling circle: moves from pay avatar position (bottom, ~70% screen height) **upward** to radial center over 1.32s
  - Push radius: 34pt × 3 = 102pt, push force: `proximity² × 60pt`
  - Uses smoothstep easing for travel
- Expanding ring: from pay avatar position, radius 16→1000pt over 2.97s
  - Stroke width: 20–30pt, linear fade
  - Pushes nearby dots outward by up to 12pt
- Pay wave intensity → dot size scaling up to 1.5× + chromatic aberration
- Deactivates after 3s

## Search Circle Wandering

The search circle uses multi-sine chaotic wandering to produce non-repeating, organic paths:

```
targetX = centerX
    + sin(phaseA) * rangeX * 0.6
    + sin(phaseB * 1.3 + 0.7) * rangeX * 0.3
    + cos(phaseC * 0.8 + 2.1) * rangeX * 0.15

targetY = centerY
    + cos(phaseA * 0.9 + 1.2) * rangeY * 0.5
    + sin(phaseD * 1.1 + 0.4) * rangeY * 0.35
    + cos(phaseB * 0.7 + 3.0) * rangeY * 0.15
```

- Four phase angles advance at different speeds (0.012 × [1.0, 1.7, 0.6, 2.3] per frame at 60fps)
- Wander range: 42% of canvas width/height
- Position tracked via spring (k=6.0, damping=0.82)
- Clamped inside canvas bounds with 22pt padding

## Easing Functions

- **smoothstep** (Hermite): `3t² - 2t³` — C1 continuous, used by formation and search circle
- **smootherStep** (Perlin): `6t⁵ - 15t⁴ + 10t³` — C2 continuous, available for smoother transitions
- **easeOutSpring**: Damped oscillation `1 - e^(-8t) * cos(12t * 0.6)`
- **easeOutCubic**: `1 - (1-t)³`
- **lerp**: `a + (b - a) * t`

## Noise Field (Optional Mode)

An alternative motion mode using 3D simplex noise for organic drift:
- Noise sampled at `(gridX * scale, gridY * scale, time * speed)` for X displacement
- Second sample with offset seeds `(+31.7, +47.3)` for decorrelated Y displacement
- Default parameters: speed=0.15, scale=0.05, amplitude=4pt
- Produces spatially coherent motion where adjacent dots move similarly

## Configuration Defaults

| Parameter | Value | Description |
|-----------|-------|-------------|
| columns | 20 | Grid columns |
| rows | 35 | Grid rows |
| dotSpacing | 18pt | Center-to-center distance |
| dotRadius | 1.5pt | Dot radius |
| baseOpacity | 0.30 | Resting opacity |
| opacityVariation | 0.08 | Per-dot random variation |
| formationDuration | 2.0s | Formation animation length |
| backgroundTransitionDuration | 1.2s | Green → black fade |
| searchRadius | 12pt | Search circle size |
| searchInfluence | 42pt | Search circle effect range |
| frozenCircleTargetRadius | 28pt | Person found repulsion size |
| waveAmplitude | 6pt | Wave mode displacement |
| noiseAmplitude | 4pt | Noise mode displacement |
| avatarRadius | 28pt | Inner ring radius (broadcast) |
| maxVisibleRadius | 165pt | Outer visible ring radius |
| visibleRingCount | 9 | Number of visible concentric rings |
| broadcastBaseOpacity | 0.42 | Radiate phase base opacity |
| waveSpeed (radiate) | 100pt/s | Concentric wave travel speed |
| waveInterval | 2.0s | Time between new wave spawns |
| waveWidth | 50pt | Width of each concentric wave |
| collapseDuration | 2.0s | Grid → rings collapse duration |
