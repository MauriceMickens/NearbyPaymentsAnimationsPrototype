//
//  DotGridCanvasView.swift
//  NearbyPaymentsAnimations
//

import SwiftUI

// MARK: - DotGridCanvasView

/// High-performance dot grid renderer using Canvas + TimelineView.
///
/// The TimelineView drives periodic updates. We pass the timeline date
/// through to a helper view so SwiftUI detects the changing input and
/// forces Canvas to re-render each frame.
struct DotGridCanvasView: View {

    var animator: DotGridAnimator

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
            DotGridCanvas(
                animator: animator,
                frameTime: context.date.timeIntervalSinceReferenceDate
            )
        }
        .background(.black)
    }
}

/// Inner view that takes frameTime as a parameter, ensuring SwiftUI
/// sees a new value each frame and re-renders the Canvas.
private struct DotGridCanvas: View {

    let animator: DotGridAnimator
    let frameTime: TimeInterval

    var body: some View {
        Canvas { context, size in
            // Setup dots if needed (first frame)
            if animator.dots.isEmpty {
                animator.setup(in: size)
            }

            // Advance animation
            animator.update(at: frameTime)

            // -- Draw green background FIRST, then dots on top --
            // Dots are visible as lighter points on the green during
            // the transition, matching the reference prototype.
            if animator.backgroundProgress < 0.99 {
                let greenOpacity = 1 - animator.backgroundProgress
                context.opacity = greenOpacity
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(red: 0.22, green: 0.44, blue: 0.15))
                )
                context.opacity = 1
            }

            // -- Draw grid dots --
            for dot in animator.dots {
                guard dot.opacity > 0.01 else { continue }
                context.opacity = dot.opacity
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.position.x - dot.radius,
                        y: dot.position.y - dot.radius,
                        width: dot.radius * 2,
                        height: dot.radius * 2
                    )),
                    with: .color(.white)
                )
            }

            // -- Draw roaming dots (brighter, with glow) --
            for dot in animator.roamingDots {
                guard dot.opacity > 0.01 else { continue }

                // Glow halo
                let gr = dot.radius * 3
                context.opacity = dot.opacity * 0.15
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.position.x - gr,
                        y: dot.position.y - gr,
                        width: gr * 2,
                        height: gr * 2
                    )),
                    with: .color(.white)
                )

                // Core
                context.opacity = dot.opacity
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dot.position.x - dot.radius,
                        y: dot.position.y - dot.radius,
                        width: dot.radius * 2,
                        height: dot.radius * 2
                    )),
                    with: .color(.white)
                )
            }
        }
    }
}
