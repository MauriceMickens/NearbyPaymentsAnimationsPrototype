//
//  DotGridAnimator.swift
//  NearbyPaymentsAnimations
//

import SwiftUI

// MARK: - Dot Model

struct Dot {
    /// Current rendered position
    var position: CGPoint
    /// Target position in the rectangular grid
    var gridPosition: CGPoint
    /// Random starting position (for chaos → formation)
    var randomPosition: CGPoint
    /// Target position in radial layout
    var radialPosition: CGPoint = .zero
    /// Current opacity (0-1)
    var opacity: Double
    /// Current radius
    var radius: Double
    /// Base opacity for this dot (slight variation per dot)
    var baseOpacity: Double
    /// Row/column index in the grid
    var row: Int
    var col: Int
    /// Random stagger delay for formation (0-1), per web implementation
    var zRainDelay: Double = 0
    /// Search circle trailing chromatic aberration intensity (0-1)
    var chaserIntensity: Double = 0
    /// Which concentric ring this dot belongs to (-1 = overflow/off-screen)
    var ringIndex: Int = -1
    /// Random scatter angle for broadcast collapse midpoint
    var scatterAngle: CGFloat = 0
    /// Random scatter magnitude for broadcast collapse midpoint
    var scatterMagnitude: CGFloat = 0
}

/// A bright dot that roams independently during scanning
struct RoamingDot {
    var position: CGPoint
    var velocity: CGPoint
    var opacity: Double
    var radius: Double
    var target: CGPoint
}

/// Expanding concentric wave ring visual during radial pulsing
struct WaveFront {
    var radius: CGFloat
    var opacity: CGFloat = 1.0
}

/// Pay wave effect: traveling orb + expanding ring displacement
struct PayWave {
    var active: Bool = false
    /// Distance of the orb from center
    var orbDistance: CGFloat = 0
    /// Direction angle of the orb (radians)
    var orbAngle: CGFloat = 0
    /// Expanding ring radius (follows behind orb)
    var ringRadius: CGFloat = 0
    /// Ring visual opacity
    var ringOpacity: CGFloat = 1.0
    /// Animation start time
    var startTime: TimeInterval = 0
}

/// Wandering search circle that displaces nearby dots (ported from web)
struct SearchCircle {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    /// Four phase angles for multi-sine chaotic wandering
    var phaseA: CGFloat = CGFloat.random(in: 0...(2 * .pi))
    var phaseB: CGFloat = CGFloat.random(in: 0...(2 * .pi))
    var phaseC: CGFloat = CGFloat.random(in: 0...(2 * .pi))
    var phaseD: CGFloat = CGFloat.random(in: 0...(2 * .pi))
    var frozen: Bool = false
    var initialized: Bool = false
}

// MARK: - Animation Phase

enum DotGridPhase: Equatable {
    case idle
    case forming          // Green → black + chaos → grid
    case scanning         // Wave sweep + roaming dots
    case personFound      // Bright dots coalesce → avatar pop
    case radialTransition // Grid → concentric circles
    case radialPulsing    // Radial with breathing animation
}

// MARK: - DotGridAnimator

/// Note: NOT @Observable — mutations happen inside Canvas render closures,
/// and @Observable would trigger infinite re-render loops. The TimelineView
/// drives continuous rendering instead.
final class DotGridAnimator {

    // MARK: - Configuration

    struct Config {
        var columns: Int = 20
        var rows: Int = 35
        var dotSpacing: CGFloat = 18
        var dotRadius: CGFloat = 1.5
        var baseOpacity: Double = 0.3
        var opacityVariation: Double = 0.08
        /// Duration for chaos → grid formation
        var formationDuration: TimeInterval = 2.0
        /// Wave speed in points per second
        var waveSpeed: CGFloat = 80
        /// Wave amplitude (dot displacement in points)
        var waveAmplitude: CGFloat = 6
        /// Wave frequency
        var waveFrequency: CGFloat = 0.15
        /// Number of roaming bright dots during scan
        var roamingDotCount: Int = 3
        /// Duration for green → black background transition
        var backgroundTransitionDuration: TimeInterval = 1.2

        /// Motion style for idle/scanning animation
        var motionStyle: MotionStyle = .wave
        /// How fast the noise field evolves (noise mode only)
        var noiseSpeed: Double = 0.15
        /// Spatial frequency of noise sampling (noise mode only)
        var noiseScale: Double = 0.05
        /// Max displacement in points from noise (noise mode only)
        var noiseAmplitude: CGFloat = 4

        enum MotionStyle: String, CaseIterable {
            case wave = "Wave"
            case noise = "Noise"
        }
    }

    var config = Config()

    // MARK: - State

    private(set) var phase: DotGridPhase = .idle
    private(set) var dots: [Dot] = []
    private(set) var roamingDots: [RoamingDot] = []
    /// Wandering search circle (displaces nearby dots during scanning)
    private(set) var searchCircle = SearchCircle()
    /// Search circle visual radius
    let searchRadius: CGFloat = 12
    /// How far the search circle affects nearby dots
    var searchInfluence: CGFloat { searchRadius * 3.5 }
    /// 0 = full green, 1 = full black. Read by DotGridCanvasView for background color.
    var backgroundProgress: Double = 0
    /// Frozen circle state for person found (exponential lerp each frame)
    private var frozenCircleRadius: CGFloat = 0
    private var frozenCircleOpacity: CGFloat = 0
    private let frozenCircleTargetRadius: CGFloat = 28

    /// Active concentric wave fronts radiating outward during pulsing
    private(set) var waveFronts: [WaveFront] = []
    /// Pay wave effect state
    private(set) var payWave = PayWave()
    /// Maximum ring index that's fully visible on screen
    private(set) var maxVisibleRing: Int = 0
    /// Time of last wave front spawn
    private var lastWaveFrontTime: TimeInterval = 0
    /// Center point for radial layout (stored for pay wave and wave fronts)
    private(set) var radialCenter: CGPoint = .zero

    /// Grid origin offset (to center the grid in the canvas)
    private var gridOrigin: CGPoint = .zero
    /// Canvas size
    private var canvasSize: CGSize = .zero

    // MARK: - Timing

    /// 1.0 = normal speed, 0.1 = 10× slower
    var timeScale: Double = 1.0

    private var phaseStartTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    /// Accumulated "animation time" that respects timeScale
    private var animationTime: TimeInterval = 0
    private var waveOrigin: CGPoint = .zero
    /// Person found position (in canvas coordinates)
    private(set) var personPosition: CGPoint = .zero
    private var personFoundTime: TimeInterval = 0

    // MARK: - Setup

    /// Initialize the dot grid for a given canvas size
    func setup(in size: CGSize) {
        canvasSize = size

        let totalGridWidth = CGFloat(config.columns - 1) * config.dotSpacing
        let totalGridHeight = CGFloat(config.rows - 1) * config.dotSpacing
        gridOrigin = CGPoint(
            x: (size.width - totalGridWidth) / 2,
            y: (size.height - totalGridHeight) / 2
        )

        dots = []
        for row in 0..<config.rows {
            for col in 0..<config.columns {
                let gridPos = CGPoint(
                    x: gridOrigin.x + CGFloat(col) * config.dotSpacing,
                    y: gridOrigin.y + CGFloat(row) * config.dotSpacing
                )

                // Web-style: dots start at grid position. Formation displacement
                // (center-outward push) is computed dynamically during updateFormation.
                let baseOpacity = config.baseOpacity +
                    Double.random(in: -config.opacityVariation...config.opacityVariation)

                dots.append(Dot(
                    position: gridPos,
                    gridPosition: gridPos,
                    randomPosition: gridPos,
                    opacity: 0,
                    radius: config.dotRadius,
                    baseOpacity: max(0.1, baseOpacity),
                    row: row,
                    col: col,
                    zRainDelay: Double.random(in: 0...1.0)
                ))
            }
        }

        setupRoamingDots()
    }

    /// Compute radial positions for each dot (for Get Paid mode).
    /// Matches web prototype: 9 visible rings, avatarRadius=28, maxVisible=165,
    /// overflow rings fade over 3 rings. No per-ring rotation offset.
    func computeRadialPositions(center: CGPoint) {
        radialCenter = center
        let avatarRadius: CGFloat = 28       // Just outside the 48px avatar
        let maxVisibleRadius: CGFloat = 165  // 9 visible rings go up to here
        let numVisibleRings = 9
        let visibleRingStep = (maxVisibleRadius - avatarRadius) / CGFloat(numVisibleRings)
        let dotSpacing: CGFloat = 15         // Arc-length between dots on each ring

        maxVisibleRing = numVisibleRings - 1

        var targets: [(angle: CGFloat, radius: CGFloat, ringIndex: Int, opacity: Double)] = []

        // Build the 9 visible rings (opacity = 1)
        for r in 0..<numVisibleRings {
            let radius = avatarRadius + CGFloat(r + 1) * visibleRingStep
            let circumference = 2 * .pi * radius
            let count = max(6, Int(circumference / dotSpacing))
            for s in 0..<count {
                let angle = CGFloat(s) / CGFloat(count) * 2 * .pi
                targets.append((angle, radius, r, 1.0))
            }
        }

        // Add overflow rings beyond the visible ones until we cover all particles
        let overflowRingStep = visibleRingStep
        var overflowRing = 0
        while targets.count < dots.count {
            overflowRing += 1
            let radius = maxVisibleRadius + CGFloat(overflowRing) * overflowRingStep
            let circumference = 2 * .pi * radius
            let count = max(6, Int(circumference / dotSpacing))
            let fadeT = min(1.0, Double(overflowRing) / 3.0)
            let ringOpacity = max(0.0, 1.0 - fadeT)
            for s in 0..<count {
                guard targets.count < dots.count else { break }
                let angle = CGFloat(s) / CGFloat(count) * 2 * .pi
                targets.append((angle, radius, numVisibleRings + overflowRing, ringOpacity))
            }
        }

        // Assign positions + scatter values to dots
        for i in dots.indices {
            let slot = targets[i % targets.count]
            dots[i].radialPosition = CGPoint(
                x: center.x + slot.radius * cos(slot.angle),
                y: center.y + slot.radius * sin(slot.angle)
            )
            dots[i].ringIndex = slot.ringIndex
            dots[i].baseOpacity = slot.opacity > 0 ? 0.35 : 0 // Broadcast base opacity
            // Random scatter for broadcast collapse (web: ±60 range)
            dots[i].scatterAngle = CGFloat.random(in: 0...(2 * .pi))
            dots[i].scatterMagnitude = CGFloat.random(in: 20...60)
        }
    }

    private func setupRoamingDots() {
        roamingDots = (0..<config.roamingDotCount).map { _ in
            let pos = CGPoint(
                x: CGFloat.random(in: 0...canvasSize.width),
                y: CGFloat.random(in: 0...canvasSize.height)
            )
            return RoamingDot(
                position: pos,
                velocity: .zero,
                opacity: 0,
                radius: config.dotRadius * 1.8,
                target: randomGridPosition()
            )
        }
    }

    private func randomGridPosition() -> CGPoint {
        guard !dots.isEmpty else { return .zero }
        let dot = dots.randomElement()!
        return dot.gridPosition
    }

    // MARK: - Phase Transitions

    func startFormation(at time: TimeInterval) {
        phase = .forming
        phaseStartTime = animationTime
        backgroundProgress = 0
        // Dots start moving immediately (hidden behind the green overlay).
        // Wave clock starts when the earliest dots are ~70% formed.
        waveStartTime = animationTime + config.formationDuration * 0.7
        // Place dots at random positions with zero opacity
        for i in dots.indices {
            dots[i].position = dots[i].randomPosition
            dots[i].opacity = 0
        }
    }

    func startScanning(at time: TimeInterval) {
        phase = .scanning
        phaseStartTime = animationTime
        waveOrigin = CGPoint(x: 0, y: canvasSize.height)
        // Hide roaming dots — search circle handles scanning visuals
        for i in roamingDots.indices {
            roamingDots[i].opacity = 0
        }
    }

    func showPerson(at position: CGPoint, time: TimeInterval) {
        personPosition = position
        personFoundTime = animationTime
        phase = .personFound
        phaseStartTime = animationTime
        // Reset frozen circle — will grow via exponential lerp each frame
        frozenCircleRadius = 0
        frozenCircleOpacity = 0
        // Hide roaming dots — search circle handles scanning visuals now
        for i in roamingDots.indices {
            roamingDots[i].opacity = 0
        }
    }

    func startRadialTransition(center: CGPoint, at time: TimeInterval) {
        computeRadialPositions(center: center)
        phase = .radialTransition
        phaseStartTime = animationTime
        waveFronts = []
        payWave.active = false
    }

    func startRadialPulsing(at time: TimeInterval) {
        phase = .radialPulsing
        phaseStartTime = animationTime
        lastWaveFrontTime = animationTime
    }

    /// Instantly snap all dots to their grid positions (useful for jumping to scanning phase)
    func snapToGrid() {
        for i in dots.indices {
            dots[i].position = dots[i].gridPosition
            dots[i].opacity = dots[i].baseOpacity
            dots[i].radius = config.dotRadius
        }
    }

    func reset() {
        phase = .idle
        backgroundProgress = 0
        for i in dots.indices {
            dots[i].position = dots[i].randomPosition
            dots[i].opacity = 0
        }
        for i in roamingDots.indices {
            roamingDots[i].opacity = 0
        }
    }

    // MARK: - Update (called every frame)

    func update(at time: TimeInterval) {
        let wallDt = lastUpdateTime > 0 ? min(time - lastUpdateTime, 1.0 / 30) : 0
        lastUpdateTime = time
        let dt = wallDt * timeScale
        animationTime += dt

        switch phase {
        case .idle:
            break
        case .forming:
            updateFormation(time: animationTime, dt: dt)
        case .scanning:
            updateScanning(time: animationTime, dt: dt)
        case .personFound:
            updatePersonFound(time: animationTime, dt: dt)
        case .radialTransition:
            updateRadialTransition(time: animationTime, dt: dt)
        case .radialPulsing:
            updateRadialPulsing(time: animationTime, dt: dt)
        }
    }

    // MARK: - Wave Displacement (shared by formation + scanning)

    /// The wave elapsed time, continuous across formation → scanning.
    /// Starts ticking once the wave begins fading in during formation.
    private var waveStartTime: TimeInterval = 0

    private func waveDisplacement(for dot: Dot, waveElapsed: TimeInterval) -> (dx: CGFloat, dy: CGFloat, envelope: CGFloat) {
        let waveFrontAngle: CGFloat = .pi / 6
        let waveFrontX = config.waveSpeed * CGFloat(waveElapsed)

        let projDist = dot.gridPosition.x * cos(waveFrontAngle)
            + dot.gridPosition.y * sin(waveFrontAngle)
        let distFromFront = projDist - waveFrontX

        let waveLength: CGFloat = canvasSize.width * 1.5
        let wrappedDist = distFromFront.truncatingRemainder(dividingBy: waveLength)

        let envelopeWidth: CGFloat = 120
        let envelope = exp(-abs(wrappedDist) / envelopeWidth)

        let displacement = config.waveAmplitude * envelope *
            sin(config.waveFrequency * projDist - CGFloat(waveElapsed) * 3)

        let perpX = -sin(waveFrontAngle)
        let perpY = cos(waveFrontAngle)

        return (perpX * displacement, perpY * displacement, envelope)
    }

    private func noiseDisplacement(for dot: Dot, time: TimeInterval) -> (dx: CGFloat, dy: CGFloat) {
        let scale = Float(config.noiseScale)
        let gx = Float(dot.gridPosition.x) * scale
        let gy = Float(dot.gridPosition.y) * scale
        let t = Float(time * config.noiseSpeed)

        let nx = SimplexNoise.noise3D(x: gx, y: gy, z: t)
        let ny = SimplexNoise.noise3D(x: gx + 31.7, y: gy + 47.3, z: t)

        return (CGFloat(nx) * config.noiseAmplitude, CGFloat(ny) * config.noiseAmplitude)
    }

    // MARK: - Formation (web-style: center-outward push + per-dot random stagger)

    private func updateFormation(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let bgDuration = config.backgroundTransitionDuration

        // --- Background fade (green → black) ---
        let bgT = min(1, elapsed / bgDuration)
        backgroundProgress = bgT

        // --- Web-style formation ---
        // fadeInProgress ramps 0→1 over 2.5s, mapped to 0→3 virtual time units.
        // Per-dot zRainDelay (0-1) staggers when each dot starts animating.
        let fadeInDuration: TimeInterval = 2.5
        let fadeInProgress = min(1.0, elapsed / fadeInDuration)
        let introTime = fadeInProgress * 3.0

        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        let maxDist = max(1, sqrt(cx * cx + cy * cy))

        var allSettled = true

        for i in dots.indices {
            let dot = dots[i]
            let delayed = max(0, introTime - dot.zRainDelay)

            // Opacity: fast (0.5 virtual time units → ~0.42s real)
            let tAlpha = min(1.0, delayed / 0.5)
            let easeAlpha = smoothStep(tAlpha)

            // Slide: slower (1.3 virtual time units → ~1.08s real)
            let tSlide = min(1.0, delayed / 1.3)
            let easeSlide = smoothStep(tSlide)

            // Push dots outward from center, proportional to distance
            let dx = dot.gridPosition.x - cx
            let dy = dot.gridPosition.y - cy
            let dist = sqrt(dx * dx + dy * dy)
            let distRatio = CGFloat(dist / maxDist)
            let push = distRatio * 156 * (1 - CGFloat(easeSlide))

            if dist > 0 {
                dots[i].position = CGPoint(
                    x: dot.gridPosition.x + (dx / dist) * push,
                    y: dot.gridPosition.y + (dy / dist) * push
                )
            } else {
                dots[i].position = dot.gridPosition
            }

            dots[i].opacity = dot.baseOpacity * easeAlpha
            dots[i].radius = config.dotRadius

            if tSlide < 1.0 || tAlpha < 1.0 { allSettled = false }
        }

        if allSettled {
            startScanning(at: time)
        }
    }

    // MARK: - Search Circle (wandering chaser, ported from web)

    private func updateSearchCircle(dt: TimeInterval) {
        guard !searchCircle.frozen else { return }

        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2

        if !searchCircle.initialized {
            searchCircle.x = cx
            searchCircle.y = cy
            searchCircle.initialized = true
        }

        // Advance phase angles for chaotic wandering
        let wanderSpeed: CGFloat = 0.012
        let dtf = CGFloat(dt * 60) // normalize to 60fps frame units

        searchCircle.phaseA += wanderSpeed * 1.0 * dtf
        searchCircle.phaseB += wanderSpeed * 1.7 * dtf
        searchCircle.phaseC += wanderSpeed * 0.6 * dtf
        searchCircle.phaseD += wanderSpeed * 2.3 * dtf

        // Combine multiple sine waves for chaotic (non-straight-line) motion
        let rangeX = canvasSize.width * 0.42
        let rangeY = canvasSize.height * 0.42

        let targetX = cx
            + sin(searchCircle.phaseA) * rangeX * 0.6
            + sin(searchCircle.phaseB * 1.3 + 0.7) * rangeX * 0.3
            + cos(searchCircle.phaseC * 0.8 + 2.1) * rangeX * 0.15
        let targetY = cy
            + cos(searchCircle.phaseA * 0.9 + 1.2) * rangeY * 0.5
            + sin(searchCircle.phaseD * 1.1 + 0.4) * rangeY * 0.35
            + cos(searchCircle.phaseB * 0.7 + 3.0) * rangeY * 0.15

        // Spring tracking toward wander target
        let springK: CGFloat = 6.0
        let damp: CGFloat = 0.82
        let dtCG = CGFloat(dt)

        searchCircle.vx += (targetX - searchCircle.x) * springK * dtCG
        searchCircle.vy += (targetY - searchCircle.y) * springK * dtCG
        searchCircle.vx *= damp
        searchCircle.vy *= damp
        searchCircle.x += searchCircle.vx * dtf
        searchCircle.y += searchCircle.vy * dtf

        // Clamp inside canvas bounds with padding
        let pad = searchRadius + 10
        searchCircle.x = max(pad, min(canvasSize.width - pad, searchCircle.x))
        searchCircle.y = max(pad, min(canvasSize.height - pad, searchCircle.y))
    }

    // MARK: - Scanning (search circle + optional wave/noise displacement)

    private func updateScanning(time: TimeInterval, dt: TimeInterval) {
        let scanElapsed = time - phaseStartTime

        // Update wandering search circle
        updateSearchCircle(dt: dt)

        let influence = searchInfluence

        for i in dots.indices {
            let dot = dots[i]

            var targetX = dot.gridPosition.x
            var targetY = dot.gridPosition.y
            var scanElevation: CGFloat = 0

            // Search circle proximity: push dots upward with bell-curve falloff
            let dxSc = dot.gridPosition.x - searchCircle.x
            let dySc = dot.gridPosition.y - searchCircle.y
            let distFromCircle = sqrt(dxSc * dxSc + dySc * dySc)

            if distFromCircle < influence {
                let proximity = 1 - distFromCircle / influence
                let bell = CGFloat(smoothStep(Double(proximity)))
                scanElevation = bell
                // Push dot upward (negative Y = up) to simulate Z lift
                targetY -= bell * 12
                // Track chaser intensity for chromatic aberration
                dots[i].chaserIntensity = max(dots[i].chaserIntensity, Double(bell))
            }

            // Decay chaser intensity (~1s to fully fade)
            if dots[i].chaserIntensity > 0 {
                dots[i].chaserIntensity = max(0, dots[i].chaserIntensity - dt * 1.0)
            }

            // Web-style: dots are stationary. Only the search circle displaces them.
            dots[i].opacity = min(1, dot.baseOpacity + Double(scanElevation) * 0.65)
            dots[i].radius = config.dotRadius * (1 + scanElevation * 0.8)
            dots[i].position = CGPoint(x: targetX, y: targetY)
        }
    }

    private func updateRoamingDots(dt: TimeInterval, elapsed: TimeInterval) {
        // Fade in roaming dots
        let roamOpacity = min(1, elapsed / 0.5)

        for i in roamingDots.indices {
            let dot = roamingDots[i]

            // Move toward target with smooth steering
            let dx = dot.target.x - dot.position.x
            let dy = dot.target.y - dot.position.y
            let dist = sqrt(dx * dx + dy * dy)

            if dist < 10 {
                // Pick a new target
                roamingDots[i].target = randomGridPosition()
            }

            let speed: CGFloat = 60
            let steerStrength: CGFloat = 3

            let desiredVx = (dx / max(dist, 1)) * speed
            let desiredVy = (dy / max(dist, 1)) * speed

            roamingDots[i].velocity.x += (desiredVx - dot.velocity.x) * steerStrength * CGFloat(dt)
            roamingDots[i].velocity.y += (desiredVy - dot.velocity.y) * steerStrength * CGFloat(dt)

            roamingDots[i].position.x += roamingDots[i].velocity.x * CGFloat(dt)
            roamingDots[i].position.y += roamingDots[i].velocity.y * CGFloat(dt)

            roamingDots[i].opacity = roamOpacity * 0.9
            roamingDots[i].radius = config.dotRadius * 2.0
        }
    }

    // MARK: - Person Found (web-style: frozen circle repulsion with cosine falloff)

    private func updatePersonFound(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime

        // Frozen circle grows via exponential lerp (matching web animation)
        // Circle starts growing after 200ms delay, matching avatar appearance
        if elapsed > 0.2 {
            frozenCircleRadius += (frozenCircleTargetRadius - frozenCircleRadius) * CGFloat(dt) * 5
            frozenCircleOpacity = min(1, frozenCircleOpacity + CGFloat(dt) * 3)
        }

        let influenceR = frozenCircleTargetRadius * 3.0

        for i in dots.indices {
            let dx = dots[i].gridPosition.x - personPosition.x
            let dy = dots[i].gridPosition.y - personPosition.y
            let dist = sqrt(dx * dx + dy * dy)

            if dist < influenceR && dist > 0.1 && frozenCircleRadius > 0.5 {
                let normDx = dx / dist
                let normDy = dy / dist

                // Web-style repulsion: strong inside circle, cosine falloff outside
                let pushStrength: CGFloat
                if dist < frozenCircleRadius {
                    pushStrength = (influenceR - dist) * 1.5
                } else {
                    let t = (dist - frozenCircleRadius) / max(1, influenceR - frozenCircleRadius)
                    let falloff = 0.5 * (1 + cos(t * .pi))
                    pushStrength = falloff * frozenCircleRadius * 0.8
                }

                dots[i].position = CGPoint(
                    x: dots[i].gridPosition.x + normDx * pushStrength * frozenCircleOpacity,
                    y: dots[i].gridPosition.y + normDy * pushStrength * frozenCircleOpacity
                )
            } else {
                dots[i].position = CGPoint(
                    x: lerp(dots[i].position.x, dots[i].gridPosition.x, CGFloat(dt) * 4),
                    y: lerp(dots[i].position.y, dots[i].gridPosition.y, CGFloat(dt) * 4)
                )
            }

            // Decay chaser intensity during person found phase
            if dots[i].chaserIntensity > 0 {
                dots[i].chaserIntensity = max(0, dots[i].chaserIntensity - dt * 2.0)
            }

            dots[i].opacity = dots[i].baseOpacity
            dots[i].radius = config.dotRadius
        }
    }

    // MARK: - Radial Transition (broadcast collapse, matches web prototype)

    private func updateRadialTransition(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let duration: TimeInterval = 2.0

        for i in dots.indices {
            let dot = dots[i]

            // Per-particle tiny delay (web: transDelay * 0.05)
            let delayed = max(0, elapsed - dot.zRainDelay * 0.05)
            let t = min(1.0, delayed / duration)
            // Sine-based ease-in-out (matching web)
            let ease = CGFloat((1 - cos(t * .pi)) * 0.5)

            let fromPos = dot.gridPosition
            let toPos = dot.radialPosition

            // Per-particle scatter: peaks at midpoint via sin(t*π)
            let scatterEnvelope = sin(CGFloat(t) * .pi)
            let scatterX = cos(dot.scatterAngle) * dot.scatterMagnitude * scatterEnvelope
            let scatterY = sin(dot.scatterAngle) * dot.scatterMagnitude * scatterEnvelope

            let baseX = lerp(fromPos.x, toPos.x, ease)
            let baseY = lerp(fromPos.y, toPos.y, ease)

            dots[i].position = CGPoint(
                x: baseX + scatterX,
                y: baseY + scatterY
            )

            // Overflow opacity: gradually apply slot opacity during ease
            // Web: slotOpacity = 1 - (1 - slot.opacity) * ease
            let slotOpacity = 1.0 - (1.0 - dot.baseOpacity) * Double(ease)
            dots[i].opacity = 0.35 * slotOpacity
            dots[i].radius = config.dotRadius
        }

        if elapsed >= duration + 0.1 {
            startRadialPulsing(at: time)
        }
    }

    // MARK: - Radial Pulsing

    private func updateRadialPulsing(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime

        // Advance pay wave if active
        if payWave.active {
            updatePayWave(time: time, dt: dt)
        }

        // Web-style: dots are stationary at ring positions.
        // Visual movement comes from opacity-only concentric waves.
        let waveSpeed: CGFloat = 100       // pt/s
        let waveInterval: TimeInterval = 2.0
        let waveWidth: CGFloat = 50
        let numWaves = Int(elapsed / waveInterval) + 1

        for i in dots.indices {
            let dot = dots[i]
            var posX = dot.radialPosition.x
            var posY = dot.radialPosition.y
            let dx = posX - radialCenter.x
            let dy = posY - radialCenter.y
            let dist = sqrt(dx * dx + dy * dy)

            // Concentric opacity waves (no displacement)
            var waveAlphaBoost: Double = 0
            for w in 0..<numWaves {
                let waveAge = elapsed - Double(w) * waveInterval
                guard waveAge >= 0 else { continue }
                let waveFront = CGFloat(waveAge) * waveSpeed
                let distFromWave = abs(dist - waveFront)
                if distFromWave < waveWidth {
                    let strength = Double(1 - distFromWave / waveWidth)
                    let fade = max(0, 1 - waveAge / 5.0)
                    waveAlphaBoost = max(waveAlphaBoost, strength * fade)
                }
            }

            // Pay wave: traveling circle + expanding ring displacement
            var payWaveIntensity: CGFloat = 0
            if payWave.active {
                let pwElapsed = time - payWave.startTime
                let pwCx = radialCenter.x
                let pwStartY = canvasSize.height * 0.7  // Pay avatar position (bottom area)
                let pwEndY = radialCenter.y              // Circle center
                let travelDist = pwStartY - pwEndY
                let travelDuration: TimeInterval = 1.32
                let circleRadius: CGFloat = 34

                let beforeX = posX
                let beforeY = posY

                // Effect 1: Circle traveling upward
                if pwElapsed < travelDuration {
                    let t = CGFloat(pwElapsed / travelDuration)
                    let ease = t * t * (3 - 2 * t)
                    let ballY = pwStartY - travelDist * ease
                    let pdx = posX - pwCx
                    let pdy = posY - ballY
                    let pDist = sqrt(pdx * pdx + pdy * pdy)
                    if pDist < circleRadius * 3 && pDist > 0.1 {
                        let proximity = 1 - pDist / (circleRadius * 3)
                        let pushForce = proximity * proximity * 60
                        let nx = pdx / pDist
                        let ny = pdy / pDist
                        posX += nx * pushForce
                        posY += ny * pushForce * 0.3
                    }
                }

                // Effect 2: Expanding ring from pay avatar position
                let ringDuration: TimeInterval = 2.97
                if pwElapsed < ringDuration {
                    let t = CGFloat(pwElapsed / ringDuration)
                    let ease = 1 - (1 - t) * (1 - t) // ease-out
                    let ringRadius = 16 + ease * 984
                    let ringStroke: CGFloat = 20 + (1 - t) * 10
                    let rdx = posX - pwCx
                    let rdy = posY - pwStartY
                    let rDist = sqrt(rdx * rdx + rdy * rdy)
                    let distFromRing = abs(rDist - ringRadius)
                    if distFromRing < ringStroke && rDist > 0.1 {
                        let ringStrength = 1 - distFromRing / ringStroke
                        let fade = max(0, 1 - t)
                        let push = ringStrength * fade * 12
                        let nx = rdx / rDist
                        let ny = rdy / rDist
                        posX += nx * push
                        posY += ny * push
                    }
                }

                let totalDisp = sqrt(pow(posX - beforeX, 2) + pow(posY - beforeY, 2))
                payWaveIntensity = min(1, totalDisp / 30)
            }

            dots[i].position = CGPoint(x: posX, y: posY)

            // Opacity: broadcast base 0.42 + wave alpha boost up to 0.48
            let broadcastFade = dot.baseOpacity > 0 ? 1.0 : 0.0
            let alpha = (0.42 + waveAlphaBoost * 0.48) * broadcastFade
            dots[i].opacity = min(1, alpha)

            // Size: pay wave scales up to 1.5×
            let waveScale = 1 + payWaveIntensity * 0.5
            dots[i].radius = config.dotRadius * waveScale

            // Chromatic aberration from pay wave
            dots[i].chaserIntensity = Double(payWaveIntensity)
        }

        // Decay pay wave intensity when not active
        if !payWave.active {
            for i in dots.indices {
                if dots[i].chaserIntensity > 0 {
                    dots[i].chaserIntensity = max(0, dots[i].chaserIntensity - dt * 2)
                }
            }
        }
    }

    // MARK: - Pay Wave

    /// Trigger a pay wave effect (traveling circle from bottom upward + expanding ring)
    func triggerPayWave() {
        guard phase == .radialPulsing else { return }
        payWave = PayWave(
            active: true,
            orbDistance: 0,
            orbAngle: 0,
            ringRadius: 0,
            ringOpacity: 1.0,
            startTime: animationTime
        )
    }

    private func updatePayWave(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - payWave.startTime
        // Deactivate after both effects complete
        if elapsed > 3.0 {
            payWave.active = false
        }
    }

    // MARK: - Easing Functions

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func easeOutSpring(_ t: Double) -> CGFloat {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let dampening = 0.6
        let x = CGFloat(t)
        return 1 - CGFloat(pow(M_E, -8 * Double(x))) * CGFloat(cos(12 * Double(x) * dampening))
    }

    private func easeOutCubic(_ t: Double) -> CGFloat {
        let t = CGFloat(min(1, max(0, t)))
        return 1 - pow(1 - t, 3)
    }

    /// Hermite smoothStep — C1 continuous (3t²-2t³). Used by web version.
    private func smoothStep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// Perlin's smootherStep — C2 continuous. Zero velocity AND zero
    /// acceleration at both endpoints. Reaches exactly 1.0.
    private func smootherStep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

// MARK: - Simplex Noise

/// Minimal 3D simplex noise for dot grid drift animation.
enum SimplexNoise {

    static func noise3D(x: Float, y: Float, z: Float) -> Float {
        let F3: Float = 1.0 / 3.0
        let G3: Float = 1.0 / 6.0

        let s = (x + y + z) * F3
        let i = Int32(floor(x + s))
        let j = Int32(floor(y + s))
        let k = Int32(floor(z + s))

        let t = Float(i + j + k) * G3
        let x0 = x - (Float(i) - t)
        let y0 = y - (Float(j) - t)
        let z0 = z - (Float(k) - t)

        let (i1, j1, k1, i2, j2, k2): (Int32, Int32, Int32, Int32, Int32, Int32)
        if x0 >= y0 {
            if y0 >= z0      { (i1,j1,k1,i2,j2,k2) = (1,0,0,1,1,0) }
            else if x0 >= z0 { (i1,j1,k1,i2,j2,k2) = (1,0,0,1,0,1) }
            else              { (i1,j1,k1,i2,j2,k2) = (0,0,1,1,0,1) }
        } else {
            if y0 < z0       { (i1,j1,k1,i2,j2,k2) = (0,0,1,0,1,1) }
            else if x0 < z0  { (i1,j1,k1,i2,j2,k2) = (0,1,0,0,1,1) }
            else              { (i1,j1,k1,i2,j2,k2) = (0,1,0,1,1,0) }
        }

        let x1 = x0 - Float(i1) + G3
        let y1 = y0 - Float(j1) + G3
        let z1 = z0 - Float(k1) + G3
        let x2 = x0 - Float(i2) + 2.0 * G3
        let y2 = y0 - Float(j2) + 2.0 * G3
        let z2 = z0 - Float(k2) + 2.0 * G3
        let x3 = x0 - 1.0 + 3.0 * G3
        let y3 = y0 - 1.0 + 3.0 * G3
        let z3 = z0 - 1.0 + 3.0 * G3

        let ii = Int(i & 255)
        let jj = Int(j & 255)
        let kk = Int(k & 255)

        let gi0 = Self.perm[ii +       Self.perm[jj +       Self.perm[kk]]] % 12
        let gi1 = Self.perm[ii + Int(i1) + Self.perm[jj + Int(j1) + Self.perm[kk + Int(k1)]]] % 12
        let gi2 = Self.perm[ii + Int(i2) + Self.perm[jj + Int(j2) + Self.perm[kk + Int(k2)]]] % 12
        let gi3 = Self.perm[ii + 1 +    Self.perm[jj + 1 +    Self.perm[kk + 1]]] % 12

        return 32.0 * (contrib(gi0, x0, y0, z0) +
                        contrib(gi1, x1, y1, z1) +
                        contrib(gi2, x2, y2, z2) +
                        contrib(gi3, x3, y3, z3))
    }

    private static func contrib(_ gi: Int, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let t = 0.6 - x * x - y * y - z * z
        guard t > 0 else { return 0 }
        let t2 = t * t
        let g = grad3[gi]
        return t2 * t2 * (g.0 * x + g.1 * y + g.2 * z)
    }

    private static let grad3: [(Float, Float, Float)] = [
        (1,1,0),(-1,1,0),(1,-1,0),(-1,-1,0),
        (1,0,1),(-1,0,1),(1,0,-1),(-1,0,-1),
        (0,1,1),(0,-1,1),(0,1,-1),(0,-1,-1)
    ]

    private static let perm: [Int] = {
        let p: [Int] = [
            151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
            140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
            247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
            57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
            74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
            60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
            65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
            200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
            52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
            207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
            119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
            129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
            218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
            81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
            184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
            222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
        ]
        return p + p
    }()
}
