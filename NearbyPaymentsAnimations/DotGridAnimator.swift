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
    case forming          // Chaos → grid
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
        var columns: Int = 25
        var rows: Int = 20
        var dotSpacing: CGFloat = 14
        var dotRadius: CGFloat = 1.8
        var baseOpacity: Double = 0.35
        var opacityVariation: Double = 0.1
        /// Duration for chaos → grid formation
        var formationDuration: TimeInterval = 1.2
        /// Wave speed in points per second
        var waveSpeed: CGFloat = 80
        /// Wave amplitude (dot displacement in points)
        var waveAmplitude: CGFloat = 6
        /// Wave frequency
        var waveFrequency: CGFloat = 0.15
        /// Number of roaming bright dots during scan
        var roamingDotCount: Int = 3
    }

    var config = Config()

    // MARK: - State

    private(set) var phase: DotGridPhase = .idle
    private(set) var dots: [Dot] = []
    private(set) var roamingDots: [RoamingDot] = []

    /// Grid origin offset (to center the grid in the canvas)
    private var gridOrigin: CGPoint = .zero
    /// Canvas size
    private var canvasSize: CGSize = .zero

    // MARK: - Timing

    private var phaseStartTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
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

                // Random starting position (scattered across canvas + some overflow)
                let randomPos = CGPoint(
                    x: CGFloat.random(in: -30...(size.width + 30)),
                    y: CGFloat.random(in: -30...(size.height + 30))
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
        phaseStartTime = time
    }

    func startScanning(at time: TimeInterval) {
        phase = .scanning
        phaseStartTime = time
        waveOrigin = CGPoint(x: 0, y: canvasSize.height)
    }

    func showPerson(at position: CGPoint, time: TimeInterval) {
        personPosition = position
        personFoundTime = time
        phase = .personFound
        phaseStartTime = time
    }

    func startRadialTransition(center: CGPoint, at time: TimeInterval) {
        computeRadialPositions(center: center)
        phase = .radialTransition
        phaseStartTime = time
    }

    func startRadialPulsing(at time: TimeInterval) {
        phase = .radialPulsing
        phaseStartTime = time
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
        let dt = lastUpdateTime > 0 ? min(time - lastUpdateTime, 1.0 / 30) : 0
        lastUpdateTime = time

        switch phase {
        case .idle:
            break
        case .forming:
            updateFormation(time: time, dt: dt)
        case .scanning:
            updateScanning(time: time, dt: dt)
        case .personFound:
            updatePersonFound(time: time, dt: dt)
        case .radialTransition:
            updateRadialTransition(time: time, dt: dt)
        case .radialPulsing:
            updateRadialPulsing(time: time, dt: dt)
        }
    }

    // MARK: - Formation (chaos → grid)

    private func updateFormation(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime
        let duration = config.formationDuration

        for i in dots.indices {
            // Stagger based on distance from center of grid
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            let dx = dots[i].gridPosition.x - centerX
            let dy = dots[i].gridPosition.y - centerY
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist = sqrt(centerX * centerX + centerY * centerY)
            let stagger = Double(dist / maxDist) * 0.4

            let localT = max(0, min(1, (elapsed - stagger) / (duration - stagger)))
            let eased = easeOutSpring(localT)

            dots[i].position = CGPoint(
                x: lerp(dots[i].randomPosition.x, dots[i].gridPosition.x, eased),
                y: lerp(dots[i].randomPosition.y, dots[i].gridPosition.y, eased)
            )

            // Fade in during formation
            let opacityT = min(1, elapsed / (duration * 0.6))
            dots[i].opacity = dots[i].baseOpacity * opacityT
            dots[i].radius = config.dotRadius
        }

        // Auto-transition to scanning when done
        if elapsed >= duration + 0.3 {
            startScanning(at: time)
        }
    }

    // MARK: - Scanning (wave sweep)

    private func updateScanning(time: TimeInterval, dt: TimeInterval) {
        let elapsed = time - phaseStartTime

        // Wave front position - sweeps diagonally
        let waveFrontX = config.waveSpeed * CGFloat(elapsed)
        let waveFrontAngle: CGFloat = .pi / 6 // ~30° diagonal

        for i in dots.indices {
            let dot = dots[i]

            // Project dot position onto wave direction
            let projDist = dot.gridPosition.x * cos(waveFrontAngle)
                + dot.gridPosition.y * sin(waveFrontAngle)

            // Distance from wave front along wave direction
            let distFromFront = projDist - waveFrontX

            // Wrap the wave so it repeats
            let waveLength: CGFloat = canvasSize.width * 1.5
            let wrappedDist = distFromFront.truncatingRemainder(dividingBy: waveLength)

            // Displacement envelope: strong near front, decays quickly
            let envelopeWidth: CGFloat = 120
            let envelope = exp(-abs(wrappedDist) / envelopeWidth)

            // Sinusoidal displacement perpendicular to wave direction
            let displacement = config.waveAmplitude * envelope *
                sin(config.waveFrequency * projDist - CGFloat(elapsed) * 3)

            let perpX = -sin(waveFrontAngle)
            let perpY = cos(waveFrontAngle)

            dots[i].position = CGPoint(
                x: dot.gridPosition.x + perpX * displacement,
                y: dot.gridPosition.y + perpY * displacement
            )

            // Modulate opacity with wave
            let opacityBoost = Double(envelope) * 0.4
            dots[i].opacity = dot.baseOpacity + opacityBoost
            dots[i].radius = config.dotRadius + CGFloat(envelope) * 0.8
        }

        // Update roaming dots
        updateRoamingDots(dt: dt, elapsed: elapsed)
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
}
