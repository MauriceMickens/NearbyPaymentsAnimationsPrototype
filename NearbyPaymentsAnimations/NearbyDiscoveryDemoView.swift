//
//  NearbyDiscoveryDemoView.swift
//  NearbyPaymentsAnimations
//

import SwiftUI

// MARK: - NearbyDiscoveryDemoView

/// Full-screen demo that simulates the nearby discovery animation flow.
///
/// Starts with a green screen (representing Cash App). Tapping the "Nearby"
/// button triggers the green → black transition into the dot grid animation.
struct NearbyDiscoveryDemoView: View {

    @State private var animator = DotGridAnimator()
    @State private var showDiscoveryUI = false
    @State private var showAvatar = false
    @State private var avatarOpacity: Double = 0
    @State private var showTitle = false
    @State private var titleText = ""
    @State private var selectedMode: NearbyMode = .pay
    @State private var currentPhase: AnimationPhase = .keypad

    enum AnimationPhase: String, CaseIterable {
        case keypad = "Keypad"
        case scanning = "Scanning"
        case personFound = "Person Found"
        case radial = "Radial"
    }

    enum NearbyMode: String, CaseIterable {
        case pay = "Pay"
        case getPaid = "Get Paid"
    }

    var body: some View {
        ZStack {
            // Canvas (always present — draws green bg when idle, black + dots when animating)
            DotGridCanvasView(animator: animator)
                .ignoresSafeArea()

            // Green keypad overlay — simple green screen with Nearby button
            if currentPhase == .keypad {
                keypadOverlay
                    .opacity(animator.backgroundProgress < 0.01 ? 1 : 0)
            }

            // Discovery UI (title bar, avatar, mode toggle)
            if showDiscoveryUI {
                VStack(spacing: 0) {
                    if showTitle {
                        discoveryTitleBar
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    if showAvatar {
                        avatarView
                            .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()
                }
            }

            // Controls
            VStack {
                Spacer()
                controlsPanel
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Green Keypad Overlay

    private var keypadOverlay: some View {
        ZStack {
            Color(red: 0.0, green: 0.54, blue: 0.15)
                .ignoresSafeArea()

            Button(action: { startNearbyFlow() }) {
                VStack(spacing: 8) {
                    Image(systemName: "sensor.tag.radiowaves.forward")
                        .font(.system(size: 32, weight: .medium))
                    Text("Nearby")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.2))
                )
            }
        }
    }

    // MARK: - Discovery Title Bar

    private var discoveryTitleBar: some View {
        HStack {
            Button(action: { resetToKeypad() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }

            Spacer()

            Text(titleText)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Spacer()

            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.gray.opacity(0.6), .gray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.8))
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.3), lineWidth: 2)
                )

            Text("Elisa W.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
        .opacity(avatarOpacity)
        .offset(x: 60, y: -20)
    }

    // MARK: - Mode Toggle Bar

    private var modeToggleBar: some View {
        HStack(spacing: 12) {
            modeButton(title: "Pay", mode: .pay)
            modeButton(title: "Get paid", mode: .getPaid)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func modeButton(title: String, mode: NearbyMode) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMode = mode
            }
            handleModeChange(mode)
        }) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectedMode == mode ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(selectedMode == mode ? .white.opacity(0.15) : .clear)
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnimationPhase.allCases, id: \.self) { phase in
                        Button(action: { goToPhase(phase) }) {
                            Text(phase.rawValue)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(currentPhase == phase ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(currentPhase == phase ? .white : .white.opacity(0.15))
                                )
                        }
                    }

                    Button(action: { startNearbyFlow() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Auto")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.green))
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 16) {
                configSlider(label: "Dots", value: Binding(
                    get: { Double(animator.config.columns) },
                    set: { animator.config.columns = Int($0); refreshGrid() }
                ), range: 10...40)

                configSlider(label: "Space", value: Binding(
                    get: { Double(animator.config.dotSpacing) },
                    set: { animator.config.dotSpacing = CGFloat($0); refreshGrid() }
                ), range: 8...24)

                configSlider(label: "Wave", value: Binding(
                    get: { Double(animator.config.waveAmplitude) },
                    set: { animator.config.waveAmplitude = CGFloat($0) }
                ), range: 0...20)

                configSlider(label: "Speed", value: Binding(
                    get: { animator.timeScale },
                    set: { animator.timeScale = $0 }
                ), range: 0.05...1.0)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.8))
    }

    private func configSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: value, in: range)
                .tint(.white.opacity(0.5))
        }
    }

    // MARK: - Flow Control

    private func ensureSetup() {
        if animator.dots.isEmpty {
            animator.setup(in: UIScreen.main.bounds.size)
        }
    }

    private func startNearbyFlow() {
        ensureSetup()
        currentPhase = .scanning
        let time = Date().timeIntervalSinceReferenceDate
        let speed = max(0.01, animator.timeScale)
        animator.reset()
        animator.startFormation(at: time)

        // Hide keypad, show discovery UI after a beat
        // Scale delays by 1/timeScale so they match animation time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 / speed) { [self] in
            withAnimation(.easeInOut(duration: 0.3)) {
                showDiscoveryUI = true
            }
        }

        // Show title after grid forms
        let titleDelay = (animator.config.backgroundTransitionDuration + 0.8) / speed
        DispatchQueue.main.asyncAfter(deadline: .now() + titleDelay) { [self] in
            guard currentPhase == .scanning else { return }
            withAnimation(.easeIn(duration: 0.5)) {
                showTitle = true
                titleText = "Looking for people nearby"
            }
        }

        // Person found after scanning runs for a while
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0 / speed) { [self] in
            guard currentPhase == .scanning else { return }
            goToPhase(.personFound)
        }
    }

    private func goToPhase(_ phase: AnimationPhase) {
        ensureSetup()
        currentPhase = phase
        let time = Date().timeIntervalSinceReferenceDate

        switch phase {
        case .keypad:
            resetToKeypad()

        case .scanning:
            if animator.phase != .scanning {
                animator.snapToGrid()
                animator.backgroundProgress = 1
                animator.startScanning(at: time)
            }
            showDiscoveryUI = true
            showAvatar = false
            avatarOpacity = 0
            withAnimation {
                showTitle = true
                titleText = "Looking for people nearby"
            }

        case .personFound:
            // Only snap to grid if we're jumping here from idle/keypad.
            // If still forming, let formation finish naturally first.
            if animator.phase == .idle {
                animator.snapToGrid()
                animator.backgroundProgress = 1
            } else if animator.phase == .forming {
                // Don't snap — wait for formation to complete on its own.
                // The animator will transition to scanning when all dots settle.
                return
            }
            showDiscoveryUI = true
            let size = UIScreen.main.bounds.size
            let personPos = CGPoint(x: size.width * 0.65, y: size.height * 0.4)
            animator.showPerson(at: personPos, time: time)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
                guard currentPhase == .personFound else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                    showAvatar = true
                    avatarOpacity = 1
                }
            }

        case .radial:
            showDiscoveryUI = true
            let size = UIScreen.main.bounds.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.4)
            animator.setup(in: size)
            animator.snapToGrid()
            animator.backgroundProgress = 1
            animator.startRadialTransition(center: center, at: time)
            withAnimation(.easeIn(duration: 0.4)) {
                showTitle = true
                titleText = "You're now visible to\npeople nearby"
                showAvatar = false
                avatarOpacity = 0
            }
        }
    }

    private func resetToKeypad() {
        currentPhase = .keypad
        animator.reset()
        withAnimation(.easeInOut(duration: 0.3)) {
            showDiscoveryUI = false
            showTitle = false
            showAvatar = false
            avatarOpacity = 0
        }
    }

    private func handleModeChange(_ mode: NearbyMode) {
        if mode == .getPaid {
            goToPhase(.radial)
        } else {
            goToPhase(.scanning)
        }
    }

    private func refreshGrid() {
        animator.setup(in: UIScreen.main.bounds.size)
        goToPhase(currentPhase)
    }
}

// MARK: - Preview

#Preview("Nearby Discovery Demo") {
    NearbyDiscoveryDemoView()
}
