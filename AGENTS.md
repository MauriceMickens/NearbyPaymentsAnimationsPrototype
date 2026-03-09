# Nearby Payments Animations — Agent Rules

## Grid Animation Spec Sync

The dot grid animation is implemented across three files:

- `NearbyPaymentsAnimations/DotGridAnimator.swift` — animation engine (phases, timing, dot physics)
- `NearbyPaymentsAnimations/DotGridCanvasView.swift` — 60fps Canvas renderer (drawing, chromatic aberration)
- `NearbyPaymentsAnimations/NearbyDiscoveryDemoView.swift` — UI orchestration (phase flow, controls, avatar overlay)

Accompanying specification documents live in `specs/grid-animation/`:

- `grid-animation-spec.md` — platform-agnostic design spec (source of truth for behavior)
- `grid-animation-ios.md` — iOS/SwiftUI implementation spec

### Rules

1. **Code changes require spec updates**: Any change to the animation files that alters behavior, API, visual appearance, or animation parameters must be reflected in the corresponding spec document(s).

2. **Spec changes require code updates**: Any change to the spec documents that modifies expected behavior, parameters, or visual design must be accompanied by corresponding code changes.

3. **Keep specs and code in sync**: Do not merge changes where the specs and implementation describe different behavior. If you update one, update the other in the same change.

4. **iOS code is the source of truth**: When there is ambiguity between the platform-agnostic spec and the iOS implementation, the iOS code is authoritative. Update the spec to match the code, not vice versa.
