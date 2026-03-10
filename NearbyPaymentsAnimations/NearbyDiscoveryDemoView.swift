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
    @State private var motionStyle: DotGridAnimator.Config.MotionStyle = .wave

    // Pay flow state
    @State private var showPayerAvatar = false
    @State private var showPaymentNotification = false

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

            // Discovery UI (title bar + mode toggle)
            if showDiscoveryUI {
                VStack(spacing: 0) {
                    if showTitle {
                        discoveryTitleBar
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    // Mode toggle (Pay / Get Paid) — at the very bottom
                    if currentPhase == .scanning || currentPhase == .radial {
                        modeToggleBar
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }

            // Avatar — positioned at search circle (person found) or radial center (get paid)
            GeometryReader { _ in
                let isRadial = currentPhase == .radial
                let pos = isRadial ? animator.radialCenter : animator.personPosition
                avatarView(showName: !isRadial)
                    .position(x: pos.x, y: pos.y)
                    .scaleEffect(showAvatar ? 1.0 : 0.5)
                    .opacity(showAvatar ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.5), value: showAvatar)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Payer avatar — slides up from bottom when someone pays in Get Paid mode
            VStack {
                Spacer()
                payerAvatarView
                    .offset(y: showPayerAvatar ? 0 : 30)
                    .opacity(showPayerAvatar ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: showPayerAvatar)
                    .padding(.bottom, 80)
            }
            .allowsHitTesting(false)

            // Payment notification — pinned to top, slides down from above screen
            VStack {
                paymentNotificationBanner
                    .offset(y: showPaymentNotification ? 0 : -160)
                    .opacity(showPaymentNotification ? 1 : 0)
                    .animation(
                        .spring(duration: 0.4, bounce: 0.15),
                        value: showPaymentNotification
                    )
                Spacer()
            }
            .padding(.top, 54)
            .allowsHitTesting(false)

            // Controls
            VStack {
                Spacer()
                controlsPanel
            }
        }
        .onChange(of: motionStyle) { _, newValue in
            animator.config.motionStyle = newValue
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

    private func avatarView(showName: Bool) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.gray.opacity(0.6), .gray.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.8))
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.3), lineWidth: 2)
                )

            if showName {
                Text("Elisa W.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Payer Avatar (appears at bottom when someone pays)

    private var payerAvatarView: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.gray.opacity(0.5), .gray.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.7))
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.25), lineWidth: 1.5)
                )
        }
    }

    // MARK: - Payment Notification Banner

    private var paymentNotificationBanner: some View {
        HStack(spacing: 12) {
            // Cash App icon
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0, green: 0.8, blue: 0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("$")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Payment received")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black)
                Text("Elisa W. paid you $25.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("now")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .padding(.horizontal, 8)
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

                    Button(action: { handlePay() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wave.3.forward")
                                .font(.system(size: 10))
                            Text("Pay")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.cyan))
                    }
                }
                .padding(.horizontal, 16)
            }

            Picker("Motion", selection: $motionStyle) {
                ForEach(DotGridAnimator.Config.MotionStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            HStack(spacing: 16) {
                configSlider(label: "Dots", value: Binding(
                    get: { Double(animator.config.columns) },
                    set: { animator.config.columns = Int($0); refreshGrid() }
                ), range: 10...40)

                configSlider(label: "Space", value: Binding(
                    get: { Double(animator.config.dotSpacing) },
                    set: { animator.config.dotSpacing = CGFloat($0); refreshGrid() }
                ), range: 8...24)

                if motionStyle == .wave {
                    configSlider(label: "Wave", value: Binding(
                        get: { Double(animator.config.waveAmplitude) },
                        set: { animator.config.waveAmplitude = CGFloat($0) }
                    ), range: 0...20)
                } else {
                    configSlider(label: "Drift", value: Binding(
                        get: { Double(animator.config.noiseAmplitude) },
                        set: { animator.config.noiseAmplitude = CGFloat($0) }
                    ), range: 0...10)
                }

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
            selectedMode = .pay
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
            // Use the search circle's current position — avatar appears where the chaser is
            let personPos = CGPoint(x: animator.searchCircle.x, y: animator.searchCircle.y)
            animator.showPerson(at: personPos, time: time)

            // Avatar appears quickly after chaser freezes (matching web's 200ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                guard currentPhase == .personFound else { return }
                showAvatar = true
            }

        case .radial:
            showDiscoveryUI = true
            showAvatar = false
            selectedMode = .getPaid
            let size = UIScreen.main.bounds.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Only do full setup if dots aren't initialized yet
            if animator.dots.isEmpty {
                animator.setup(in: size)
            }
            // Snap to grid only if coming from idle (dots need positions)
            if animator.phase == .idle {
                animator.snapToGrid()
            }
            animator.backgroundProgress = 1
            animator.startRadialTransition(center: center, at: time)
            withAnimation(.easeIn(duration: 0.4)) {
                showTitle = true
                titleText = "You're now visible"
            }
            // Avatar appears after collapse completes (web: 2100ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [self] in
                guard currentPhase == .radial else { return }
                showAvatar = true
            }
        }
    }

    private func resetToKeypad() {
        currentPhase = .keypad
        animator.reset()
        showPayerAvatar = false
        showPaymentNotification = false
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

    /// Trigger the pay flow: payer avatar slides up → pay wave → notification
    private func handlePay() {
        guard currentPhase == .radial else { return }

        // Step 1: Show payer avatar at bottom
        showPayerAvatar = true

        // Step 2: Fire pay wave after 250ms (avatar slides in first)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            animator.triggerPayWave()
        }

        // Step 3: Show payment notification after 1800ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [self] in
            showPaymentNotification = true
        }

        // Step 4: Auto-dismiss notification after 4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8) { [self] in
            showPaymentNotification = false
        }

        // Step 5: Hide payer avatar after wave completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [self] in
            showPayerAvatar = false
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
