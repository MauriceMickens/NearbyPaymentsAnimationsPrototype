# Grid Animation — iOS Implementation

See [grid-animation-spec.md](grid-animation-spec.md) for the platform-agnostic design spec.

## Framework

SwiftUI with Canvas (immediate-mode drawing) and TimelineView (60fps frame driver).

## Architecture

### Why Canvas, Not SwiftUI Views

The grid contains ~700 dots (20×35). Creating individual SwiftUI views per dot would be prohibitively expensive — each view carries layout, identity, and diffing overhead. Canvas provides a single draw call surface where we render all dots as raw circles, similar to HTML5 Canvas or Android's `drawBehind`.

### Why NOT @Observable

`DotGridAnimator` is a plain class, not `@Observable`. The animator is mutated inside the Canvas render closure (called 60×/second by TimelineView). If it were `@Observable`, each mutation would trigger SwiftUI state changes, causing infinite re-render loops. Instead, TimelineView drives rendering by passing a new `frameTime` each tick, which SwiftUI uses to detect that the Canvas needs redrawing.

### File Roles

| File | Responsibility |
|------|---------------|
| `DotGridAnimator.swift` | Animation engine: phases, timing, dot physics, search circle, easing. Pure computation, no rendering. |
| `DotGridCanvasView.swift` | Renderer: TimelineView + Canvas. Reads animator state, draws dots with optional chromatic aberration. |
| `NearbyDiscoveryDemoView.swift` | UI orchestration: phase buttons, sliders, avatar overlay, flow timing (delays, transitions). |

## Rendering Pipeline

```
TimelineView (60fps tick)
  → DotGridCanvas (inner view, receives frameTime)
    → animator.update(at: frameTime)    // advance physics
    → Canvas { context, size in
        // 1. Draw green overlay (if backgroundProgress < 1)
        // 2. For each dot: check chaserIntensity
        //    - If > threshold: draw RGB split with .plusLighter blend
        //    - Else: draw white circle
        // 3. Draw roaming dots with glow (legacy, currently hidden)
    }
```

The inner `DotGridCanvas` view exists so SwiftUI sees a changing `frameTime` parameter each tick and triggers Canvas re-rendering. Without it, SwiftUI would skip redraws since the animator reference doesn't change.

## Time System

Animation uses an accumulated `animationTime` that respects `timeScale`:

```swift
let wallDt = min(time - lastUpdateTime, 1.0 / 30)  // cap at 30fps minimum
let dt = wallDt * timeScale
animationTime += dt
```

- `timeScale = 1.0` is normal speed, `0.1` is 10× slower
- Phase start times and elapsed times all reference `animationTime`, not wall clock
- This allows slowing/speeding the animation without affecting the physics

## Data Models

### Dot

```swift
struct Dot {
    var position: CGPoint       // Current rendered position
    var gridPosition: CGPoint   // Resting grid position
    var randomPosition: CGPoint // Start position (currently same as grid)
    var radialPosition: CGPoint // Target for radial layout
    var opacity: Double         // Current opacity (0-1)
    var radius: Double          // Current radius in points
    var baseOpacity: Double     // Resting opacity (0.22-0.38)
    var row: Int, col: Int      // Grid indices
    var zRainDelay: Double      // Random formation stagger (0-1)
    var chaserIntensity: Double // Chromatic aberration intensity (0-1)
}
```

### SearchCircle

```swift
struct SearchCircle {
    var x, y: CGFloat           // Current position (screen coordinates)
    var vx, vy: CGFloat         // Velocity (spring tracking)
    var phaseA, phaseB, phaseC, phaseD: CGFloat  // Lissajous phase angles
    var frozen: Bool            // Freezes when person found
    var initialized: Bool       // Set on first frame
}
```

## Phase Implementations

### Formation

Driven by `updateFormation(time:dt:)`. No per-dot lerp from random→grid position. Instead, displacement is computed dynamically each frame:

```swift
let push = distRatio * 156 * (1 - smoothStep(tSlide))
position = gridPosition + normalize(gridPosition - center) * push
opacity = baseOpacity * smoothStep(tAlpha)
```

All dots start at their grid positions with zero opacity. The outward push and opacity ramp create the zoom-in effect.

### Scanning

Driven by `updateScanning(time:dt:)`. Dots are stationary at grid positions. Each frame:

1. `updateSearchCircle(dt:)` — advance Lissajous phases, spring-track toward wander target
2. For each dot: compute distance to search circle, apply bell-curve push + opacity/size boost
3. Track `chaserIntensity` for trailing chromatic aberration

### Person Found

Driven by `updatePersonFound(time:dt:)`. Uses persistent `frozenCircleRadius` and `frozenCircleOpacity` that lerp each frame (not computed from elapsed time):

```swift
frozenCircleRadius += (targetRadius - frozenCircleRadius) * dt * 5
frozenCircleOpacity = min(1, frozenCircleOpacity + dt * 3)
```

### Radial Transition

Driven by `updateRadialTransition(time:dt:)`. Pre-computes ring positions in `computeRadialPositions(center:)`. Dots lerp from grid to ring positions with spring easing and distance-based stagger.

## Chromatic Aberration Rendering

In `DotGridCanvasView`, dots with `chaserIntensity * 0.3 > 0.05` are drawn as three offset circles with additive blending:

```swift
context.blendMode = .plusLighter
// Red: offset upper-left by caOffset
// Green: center with slight Y offset
// Blue: offset lower-right by caOffset
context.blendMode = .normal
```

`caOffset = chaserIntensity * 0.3 * 3.5` — at max intensity, ~1pt offset. The `.plusLighter` blend mode means overlapping R+G+B channels produce white where aligned, with color fringes at edges.

## Avatar Overlay

The avatar is a SwiftUI view positioned in screen coordinates (matching the Canvas coordinate space):

```swift
GeometryReader { _ in
    avatarView
        .position(x: animator.personPosition.x, y: animator.personPosition.y)
        .scaleEffect(showAvatar ? 1.0 : 0.5)
        .opacity(showAvatar ? 1.0 : 0)
        .animation(.easeInOut(duration: 0.5), value: showAvatar)
}
.ignoresSafeArea()  // Critical: matches Canvas screen-space coordinates
```

The `.ignoresSafeArea()` is necessary because the Canvas ignores safe area, so its coordinate space is the full screen. Without it, the avatar would be offset by the safe area top inset (~59pt on iPhones with Dynamic Island).

## Noise Implementation

3D simplex noise (`SimplexNoise.noise3D`) using:
- Standard permutation table (doubled to 512 entries for wrapping)
- 12 gradient vectors for 3D
- Contribution function with `0.6 - x² - y² - z²` falloff
- Two decorrelated samples per dot (offset seeds +31.7, +47.3 for Y axis)

## Demo Controls

`NearbyDiscoveryDemoView` provides a development control panel:

- **Phase buttons**: Jump directly to any phase (Keypad, Scanning, Person Found, Radial)
- **Auto button**: Run the full flow with timed transitions
- **Motion picker**: Toggle between Wave and Noise modes
- **Sliders**: Dots (columns), Space (spacing), Wave/Drift amplitude, Speed (timeScale)

## Known Limitations

- `RoamingDot` struct and `updateRoamingDots` remain in code but are unused (roaming dots hidden in all phases). Can be removed in a future cleanup.
- `avatarOpacity` state variable in the demo view is set but unused after the avatar animation refactor. Can be removed.
- Wave displacement functions (`waveDisplacement`, `waveStartTime`) are unused during scanning after the web-style port. They remain for potential future use as an alternative motion style.
