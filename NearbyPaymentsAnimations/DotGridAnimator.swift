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
}

/// A bright dot that roams independently during scanning
struct RoamingDot {
    var position: CGPoint
    var velocity: CGPoint
    var opacity: Double
    var radius: Double
    var target: CGPoint
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
    }

    var config = Config()

    // MARK: - State

    private(set) var phase: DotGridPhase = .idle
    private(set) var dots: [Dot] = []
    private(set) var roamingDots: [RoamingDot] = []
    /// 0 = full green, 1 = full black. Read by DotGridCanvasView for background color.
    var backgroundProgress: Double = 0

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

                // Start off-screen: project outward from center through grid position
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let dx = gridPos.x - center.x
                let dy = gridPos.y - center.y
                let dist = max(1, sqrt(dx * dx + dy * dy))
                let nx = dx / dist
                let ny = dy / dist
                let pushDist = max(size.width, size.height) * 0.8
                let randomPos = CGPoint(
                    x: gridPos.x + nx * pushDist,
                    y: gridPos.y + ny * pushDist
                )

                let baseOpacity = config.baseOpacity +
                    Double.random(in: -config.opacityVariation...config.opacityVariation)

                dots.append(Dot(
                    position: randomPos,
                    gridPosition: gridPos,
                    randomPosition: randomPos,
                    opacity: 0,
                    radius: config.dotRadius,
                    baseOpacity: max(0.1, baseOpacity),
                    row: row,
                    col: col
                ))
            }
        }

        setupRoamingDots()
    }

    /// Compute radial positions for each dot (for Get Paid mode)
    func computeRadialPositions(center: CGPoint) {
        let maxRadius = min(canvasSize.width, canvasSize.height) * 0.42
        let ringSpacing: CGFloat = config.dotSpacing * 1.1
        let ringCount = Int(maxRadius / ringSpacing)
        let innerRadius: CGFloat = 35 // Gap for avatar

        // Distribute dots across rings
        var dotIndex = 0
        for ring in 0..<ringCount {
            let radius = innerRadius + CGFloat(ring) * ringSpacing
            let circumference = 2 * .pi * radius
            let dotsInRing = max(6, Int(circumference / (config.dotSpacing * 0.9)))

            for i in 0..<dotsInRing {
                guard dotIndex < dots.count else { return }
                let angle = (2 * .pi * CGFloat(i) / CGFloat(dotsInRing))
                    + CGFloat(ring) * 0.15 // Slight rotation offset per ring
                let pos = CGPoint(
                    x: center.x + radius * cos(angle),
                    y: center.y + radius * sin(angle)
                )
                dots[dotIndex].radialPosition = pos
                dotIndex += 1
            }
        }

        // Any remaining dots go to random positions off-screen
        while dotIndex < dots.count {
            dots[dotIndex].radialPosition = CGPoint(
                x: CGFloat.random(in: -50...(-20)),
                y: CGFloat.random(in: -50...(-20))
            )
            dotIndex += 1
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
    }

    func showPerson(at position: CGPoint, time: TimeInterval) {
        personPosition = position
        personFoundTime = animationTime
        phase = .personFound
        phaseStartTime = animationTime
    }

    func startRadialTransition(center: CGPoint, at time: TimeInterval) {
        computeRadialPositions(center: center)
        phase = .radialTransition
        phaseStartTime = animationTime
    }

    func startRadialPulsing(at time: TimeInterval) {
        phase = .radialPulsing
        phaseStartTime = animationTime
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

    // MARK: - Formation (green → black + chaos → grid + wave fade-in)

    private func updateFormation(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let bgDuration = config.backgroundTransitionDuration
        let gridDuration = config.formationDuration

        // --- Background fade (green → black) ---
        let bgT = min(1, elapsed / bgDuration)
        backgroundProgress = Double(easeOutCubic(bgT))

        // --- Grid formation starts immediately ---
        // Dots begin organizing while hidden behind the green overlay.
        // By the time the green clears, dots are already mid-animation.
        let gridElapsed = elapsed

        let waveElapsed = max(0, time - waveStartTime)

        var allSettled = true

        for i in dots.indices {
            // Stagger: edge dots arrive first, center dots last
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            let dx = dots[i].gridPosition.x - centerX
            let dy = dots[i].gridPosition.y - centerY
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist = sqrt(centerX * centerX + centerY * centerY)
            let stagger = Double(1 - dist / maxDist) * 0.6

            let localElapsed = max(0, gridElapsed - stagger)
            let t = min(1.0, localElapsed / gridDuration)
            let smooth = smootherStep(t)

            // Base position: lerp from off-screen → grid
            let baseX = lerp(dots[i].randomPosition.x, dots[i].gridPosition.x, CGFloat(smooth))
            let baseY = lerp(dots[i].randomPosition.y, dots[i].gridPosition.y, CGFloat(smooth))

            // Fade wave in per-dot during the last 30% of its formation.
            let waveWeight = CGFloat(smootherStep(max(0, min(1, (t - 0.7) / 0.3))))
            let wave = waveDisplacement(for: dots[i], waveElapsed: waveElapsed)

            dots[i].position = CGPoint(
                x: baseX + wave.dx * waveWeight,
                y: baseY + wave.dy * waveWeight
            )

            // Opacity tied to formation progress — invisible when far,
            // visible only when close to grid position
            let fadeIn = smootherStep(max(0, min(1, (t - 0.6) / 0.4)))
            let opacityBoost = Double(wave.envelope) * 0.4 * Double(waveWeight)
            dots[i].opacity = (dots[i].baseOpacity + opacityBoost) * fadeIn
            dots[i].radius = config.dotRadius + CGFloat(wave.envelope) * 0.8 * waveWeight

            if t < 1.0 { allSettled = false }
        }

        // Switch to scanning bookkeeping once all dots are settled.
        // Motion is already continuous — the wave is fully active.
        if allSettled {
            startScanning(at: time)
        }
    }

    // MARK: - Scanning (wave sweep, continues from formation)

    private func updateScanning(time: TimeInterval, dt: TimeInterval) {
        // Wave time is continuous from when it started during formation
        let waveElapsed = max(0, time - waveStartTime)
        let scanElapsed = time - phaseStartTime

        for i in dots.indices {
            let dot = dots[i]
            let wave = waveDisplacement(for: dot, waveElapsed: waveElapsed)

            dots[i].position = CGPoint(
                x: dot.gridPosition.x + wave.dx,
                y: dot.gridPosition.y + wave.dy
            )

            let opacityBoost = Double(wave.envelope) * 0.4
            dots[i].opacity = dot.baseOpacity + opacityBoost
            dots[i].radius = config.dotRadius + CGFloat(wave.envelope) * 0.8
        }

        updateRoamingDots(dt: dt, elapsed: scanElapsed)
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

    // MARK: - Person Found

    private func updatePersonFound(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime

        // Phase 1 (0-0.6s): Roaming dots converge toward person position
        // Phase 2 (0.6-1.0s): Grid dots displace outward from person, avatar appears

        let convergeEnd: TimeInterval = 0.6

        // Converge roaming dots
        for i in roamingDots.indices {
            let t = min(1, elapsed / convergeEnd)
            let eased = easeOutCubic(t)
            roamingDots[i].position = CGPoint(
                x: lerp(roamingDots[i].position.x, personPosition.x, eased * CGFloat(dt) * 5),
                y: lerp(roamingDots[i].position.y, personPosition.y, eased * CGFloat(dt) * 5)
            )

            if elapsed > convergeEnd {
                // Fade out roaming dots after convergence
                let fadeT = min(1, (elapsed - convergeEnd) / 0.3)
                roamingDots[i].opacity = max(0, 0.9 * (1 - fadeT))
            }
        }

        // Grid dots: displace away from person position
        for i in dots.indices {
            let dx = dots[i].gridPosition.x - personPosition.x
            let dy = dots[i].gridPosition.y - personPosition.y
            let dist = sqrt(dx * dx + dy * dy)

            let displacementRadius: CGFloat = 50
            let displacementStrength: CGFloat = 15

            if dist < displacementRadius && dist > 0 {
                let pushT = min(1, CGFloat(max(0, elapsed - convergeEnd)) / 0.4)
                let eased = easeOutCubic(Double(pushT))
                let pushAmount = displacementStrength * (1 - dist / displacementRadius) * CGFloat(eased)
                let nx = dx / dist
                let ny = dy / dist

                dots[i].position = CGPoint(
                    x: dots[i].gridPosition.x + nx * pushAmount,
                    y: dots[i].gridPosition.y + ny * pushAmount
                )
            } else {
                // Settle back to grid
                dots[i].position = CGPoint(
                    x: lerp(dots[i].position.x, dots[i].gridPosition.x, CGFloat(dt) * 4),
                    y: lerp(dots[i].position.y, dots[i].gridPosition.y, CGFloat(dt) * 4)
                )
            }

            dots[i].opacity = dots[i].baseOpacity
            dots[i].radius = config.dotRadius
        }
    }

    // MARK: - Radial Transition (grid → circles)

    private func updateRadialTransition(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let duration: TimeInterval = 1.4

        let t = min(1, elapsed / duration)

        for i in dots.indices {
            let dot = dots[i]

            // Stagger by distance from center
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let dx = dot.gridPosition.x - center.x
            let dy = dot.gridPosition.y - center.y
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist = sqrt(center.x * center.x + center.y * center.y)
            let stagger = Double(dist / maxDist) * 0.4

            let localT = max(0, min(1, (t * duration - stagger * duration) / (duration * 0.6)))
            let eased = easeOutSpring(localT)

            let fromPos = dot.gridPosition
            let toPos = dot.radialPosition

            dots[i].position = CGPoint(
                x: lerp(fromPos.x, toPos.x, eased),
                y: lerp(fromPos.y, toPos.y, eased)
            )

            dots[i].opacity = dot.baseOpacity
            dots[i].radius = config.dotRadius
        }

        if elapsed >= duration + 0.2 {
            startRadialPulsing(at: time)
        }
    }

    // MARK: - Radial Pulsing

    private func updateRadialPulsing(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        for i in dots.indices {
            let dot = dots[i]
            let dx = dot.radialPosition.x - center.x
            let dy = dot.radialPosition.y - center.y
            let dist = sqrt(dx * dx + dy * dy)

            // Gentle breathing/pulsing
            let pulsePhase = CGFloat(elapsed) * 1.5 - dist * 0.01
            let pulseAmount: CGFloat = 3 * sin(pulsePhase)

            if dist > 0 {
                let nx = dx / dist
                let ny = dy / dist
                dots[i].position = CGPoint(
                    x: dot.radialPosition.x + nx * pulseAmount,
                    y: dot.radialPosition.y + ny * pulseAmount
                )
            } else {
                dots[i].position = dot.radialPosition
            }

            // Subtle opacity wave radiating outward
            let opacityPulse = 0.1 * sin(Double(pulsePhase))
            dots[i].opacity = dot.baseOpacity + opacityPulse
            dots[i].radius = config.dotRadius
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

    /// Perlin's smootherStep — C2 continuous. Zero velocity AND zero
    /// acceleration at both endpoints. Reaches exactly 1.0.
    private func smootherStep(_ t: Double) -> Double {
        let x = max(0, min(1, t))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}
