//
//  NearbyDiscoveryDemoView.swift
//  NearbyPaymentsAnimations
//

import SwiftUI

// MARK: - NearbyDiscoveryDemoView

/// Full-screen demo that simulates the nearby discovery animation flow.
///
/// Provides controls to step through each animation phase and tune parameters.
struct NearbyDiscoveryDemoView: View {

    @State private var animator = DotGridAnimator()
    @State private var currentPhase: DemoPhase = .home
    @State private var showAvatar = false
    @State private var avatarOpacity: Double = 0
    @State private var showTitle = false
    @State private var titleText = ""
    @State private var selectedMode: NearbyMode = .pay

    enum DemoPhase: String, CaseIterable {
        case home = "Home"
        case forming = "Forming"
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
            // Background
            Color.black.ignoresSafeArea()

            // Dot grid
            DotGridCanvasView(animator: animator)
                .ignoresSafeArea()

            // Overlay UI
            VStack(spacing: 0) {
                // Title bar
                if showTitle {
                    titleBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Spacer()

                // Avatar (for person found)
                if showAvatar {
                    avatarView
                        .transition(.scale.combined(with: .opacity))
                }

                Spacer()

                // Bottom bar
                bottomBar
            }

            // Controls overlay
            VStack {
                Spacer()
                controlsPanel
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            autoPlay()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Button(action: { resetToHome() }) {
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
        .offset(x: 60, y: -20) // Offset from center like the design
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Group {
            if currentPhase != .home {
                HStack(spacing: 12) {
                    modeButton(title: "Pay", mode: .pay)
                    modeButton(title: "Get paid", mode: .getPaid)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentPhase)
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
            // Phase buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DemoPhase.allCases, id: \.self) { phase in
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

                    // Auto play button
                    Button(action: { autoPlay() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Auto")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(.green)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            // Config sliders
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

    // MARK: - Phase Transitions

    /// Ensure the animator has dots. GeometryReader may not have fired yet,
    /// so we fall back to screen bounds.
    private func ensureSetup() {
        if animator.dots.isEmpty {
            let size = UIScreen.main.bounds.size
            animator.setup(in: size)
        }
    }

    private func goToPhase(_ phase: DemoPhase) {
        currentPhase = phase
        ensureSetup()
        let time = Date().timeIntervalSinceReferenceDate

        switch phase {
        case .home:
            resetToHome()

        case .forming:
            animator.reset()
            animator.startFormation(at: time)
            showAvatar = false
            avatarOpacity = 0
            // Show title after formation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
                guard currentPhase == .forming else { return }
                withAnimation(.easeIn(duration: 0.5)) {
                    showTitle = true
                    titleText = "Looking for people nearby"
                }
            }

        case .scanning:
            if animator.phase != .scanning {
                animator.snapToGrid()
                animator.startScanning(at: time)
            }
            withAnimation {
                showTitle = true
                titleText = "Looking for people nearby"
                showAvatar = false
                avatarOpacity = 0
            }

        case .personFound:
            if animator.phase != .scanning && animator.phase != .personFound {
                animator.snapToGrid()
            }
            let size = UIScreen.main.bounds.size
            let personPos = CGPoint(x: size.width * 0.65, y: size.height * 0.4)
            animator.showPerson(at: personPos, time: time)

            // Show avatar after dots converge
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [self] in
                guard currentPhase == .personFound else { return }
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
                    showAvatar = true
                    avatarOpacity = 1
                }
            }

        case .radial:
            let size = UIScreen.main.bounds.size
            let center = CGPoint(x: size.width / 2, y: size.height * 0.4)
            animator.setup(in: size)
            animator.snapToGrid()
            animator.startRadialTransition(center: center, at: time)
            withAnimation(.easeIn(duration: 0.4)) {
                showTitle = true
                titleText = "You're now visible to\npeople nearby"
                showAvatar = false
                avatarOpacity = 0
            }
        }
    }

    private func resetToHome() {
        currentPhase = .home
        animator.reset()
        withAnimation {
            showTitle = false
            showAvatar = false
            avatarOpacity = 0
        }
    }

    private func handleModeChange(_ mode: NearbyMode) {
        let time = Date().timeIntervalSinceReferenceDate
        if mode == .getPaid {
            goToPhase(.radial)
        } else {
            goToPhase(.scanning)
        }
    }

    private func refreshGrid() {
        animator.setup(in: UIScreen.main.bounds.size)
        let time = Date().timeIntervalSinceReferenceDate
        goToPhase(currentPhase)
    }

    private func autoPlay() {
        goToPhase(.forming)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            goToPhase(.scanning)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            goToPhase(.personFound)
        }
    }
}

// MARK: - Preview

#Preview("Nearby Discovery Demo") {
    NearbyDiscoveryDemoView()
}

#Preview("Scanning Only") {
    let animator = DotGridAnimator()
    DotGridCanvasView(animator: animator)
        .ignoresSafeArea()
        .onAppear {
            animator.setup(in: UIScreen.main.bounds.size)
            animator.snapToGrid()
            animator.startScanning(at: Date().timeIntervalSinceReferenceDate)
        }
}
