import SwiftUI

/// Premium always-on welcome entry screen shown before the camera experience.
struct OnboardingView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showHeadline = false
    @State private var showHero = false
    @State private var showStory = false
    @State private var showCTA = false
    @State private var pulseCTA = false
    @State private var shimmerCTA = false
    @State private var isExiting = false
    @State private var isPressingCTA = false
    @State private var tiltWorld = false
    @State private var beamSweep = false
    @State private var entranceSpark = false
    @State private var pressFeedbackTick = 0
    @State private var launchFeedbackTick = 0
    @State private var orbBreathing = false
    @State private var portalBreathing = false
    @State private var tokenDrift = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = OnboardingMetrics(size: geometry.size)

            ZStack {
                background(metrics: metrics)

                ScrollView(.vertical, showsIndicators: false) {
                    content(metrics: metrics)
                        .frame(maxWidth: metrics.contentWidth)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.top, metrics.topPadding)
                        .padding(.bottom, metrics.bottomPadding)
                        .frame(maxWidth: .infinity)
                }

                if isExiting {
                    transitionGlow
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(.dark)
            .opacity(isExiting ? 0.86 : 1)
            .scaleEffect(isExiting ? 1.08 : 1)
            .rotationEffect(.degrees(isExiting ? -0.4 : 0))
            .blur(radius: isExiting && !reduceMotion ? 2.5 : 0)
            .sensoryFeedback(.selection, trigger: pressFeedbackTick)
            .sensoryFeedback(.success, trigger: launchFeedbackTick)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : .timingCurve(0.18, 0.84, 0.2, 1, duration: 0.52), value: isExiting)
            .onAppear {
                runEntranceSequence()
            }
        }
    }

    private func content(metrics: OnboardingMetrics) -> some View {
        VStack(spacing: metrics.sectionSpacing) {
            titleCluster(metrics: metrics)
                .opacity(showHeadline ? 1 : 0)
                .offset(y: showHeadline ? 0 : 18)
                .scaleEffect(showHeadline ? 1 : 0.96)
                .animation(entranceAnimation(duration: 0.68), value: showHeadline)

            heroCluster(metrics: metrics)
                .opacity(showHero ? 1 : 0)
                .offset(y: showHero ? 0 : 18)
                .scaleEffect(showHero ? 1 : 0.92)
                .animation(entranceAnimation(duration: 0.92), value: showHero)

            ctaSection(metrics: metrics)
                .opacity(showCTA ? 1 : 0)
                .offset(y: showCTA ? 0 : 22)
                .scaleEffect(showCTA ? 1 : 0.94)
                .animation(entranceAnimation(duration: 0.76), value: showCTA)
        }
        .overlay(alignment: .topTrailing) {
            cometTrail(metrics: metrics)
                .opacity(entranceSpark ? 1 : 0)
                .offset(x: entranceSpark ? metrics.heroSize * 0.08 : -metrics.heroSize * 0.2, y: entranceSpark ? -8 : 22)
                .animation(reduceMotion ? .easeOut(duration: 0.18) : .timingCurve(0.22, 0.82, 0.18, 1, duration: 1.12), value: entranceSpark)
        }
    }

    private func background(metrics: OnboardingMetrics) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.10, blue: 0.27),
                    Color(red: 0.14, green: 0.23, blue: 0.50),
                    Color(red: 0.16, green: 0.49, blue: 0.70),
                    Color(red: 0.98, green: 0.63, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 30,
                endRadius: 420
            )
            .ignoresSafeArea()
            .offset(x: -70, y: -120)

            RadialGradient(
                colors: [Color(red: 1.0, green: 0.86, blue: 0.53).opacity(0.34), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 380
            )
            .ignoresSafeArea()
            .offset(x: 60, y: 110)

            Ellipse()
                .fill(Color(red: 0.56, green: 0.96, blue: 0.87).opacity(0.22))
                .frame(width: metrics.heroSize * 1.2, height: metrics.heroSize * 0.72)
                .blur(radius: 34)
                .offset(
                    x: (metrics.useSplitLayout ? -metrics.heroSize * 0.18 : 0) + (tiltWorld ? -14 : 14),
                    y: -metrics.heroSize * 0.22 + (tiltWorld ? -10 : 10)
                )
                .animation(floatAnimation(duration: 8.5), value: tiltWorld)

            Ellipse()
                .fill(Color(red: 0.47, green: 0.65, blue: 1.0).opacity(0.16))
                .frame(width: metrics.heroSize * 1.35, height: metrics.heroSize * 0.78)
                .blur(radius: 40)
                .offset(
                    x: (metrics.useSplitLayout ? metrics.heroSize * 0.22 : 0) + (tiltWorld ? 16 : -12),
                    y: metrics.heroSize * 0.36 + (tiltWorld ? 12 : -8)
                )
                .animation(floatAnimation(duration: 7.4), value: tiltWorld)

            starfield
        }
    }

    private var starfield: some View {
        GeometryReader { geometry in
            ForEach(Array(stars.enumerated()), id: \.offset) { index, star in
                Circle()
                    .fill(star.color.opacity(star.opacity))
                    .frame(width: star.size, height: star.size)
                    .overlay {
                        Circle()
                            .stroke(star.color.opacity(0.35), lineWidth: 1)
                            .scaleEffect(1.8)
                    }
                    .position(
                        x: geometry.size.width * star.x,
                        y: geometry.size.height * star.y
                    )
                    .scaleEffect(showHero ? star.expandedScale : 0.45)
                    .opacity(showHero ? star.opacity : 0.18)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) :
                            .easeInOut(duration: star.duration)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: showHero
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func titleCluster(metrics: OnboardingMetrics) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Your drawing\nwakes up.")
                    .font(.system(size: metrics.titleFontSize, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .lineSpacing(metrics.titleLineSpacing)

                Text("Draw. Scan. Alive.")
                    .font(.system(size: metrics.subtitleFontSize, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private func heroCluster(metrics: OnboardingMetrics) -> some View {
        ZStack {
            heroIllustration(metrics: metrics)
                .frame(maxWidth: metrics.useSplitLayout ? metrics.heroSize * 1.18 : .infinity)

            flowToken(
                title: "Draw",
                tint: Color(red: 1.0, green: 0.78, blue: 0.42),
                angle: -10,
                metrics: metrics
            )
            .offset(x: -metrics.heroSize * 0.36, y: -metrics.heroSize * 0.26)
            .opacity(showStory ? 1 : 0)
            .animation(entranceAnimation(duration: 0.52).delay(reduceMotion ? 0 : 0.02), value: showStory)

            flowToken(
                title: "Scan",
                tint: Color(red: 0.49, green: 0.93, blue: 0.85),
                angle: 7,
                metrics: metrics
            )
            .offset(x: metrics.heroSize * 0.02, y: metrics.heroSize * 0.34)
            .opacity(showStory ? 1 : 0)
            .animation(entranceAnimation(duration: 0.56).delay(reduceMotion ? 0 : 0.08), value: showStory)

            flowToken(
                title: "Alive",
                tint: Color(red: 1.0, green: 0.63, blue: 0.30),
                angle: -6,
                metrics: metrics
            )
            .offset(x: metrics.heroSize * 0.36, y: -metrics.heroSize * 0.18)
            .opacity(showStory ? 1 : 0)
            .animation(entranceAnimation(duration: 0.56).delay(reduceMotion ? 0 : 0.14), value: showStory)
        }
        .frame(maxWidth: .infinity)
    }

    private func heroIllustration(metrics: OnboardingMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.heroCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.heroCornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: metrics.heroCornerRadius - 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.11),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(6)

            Path { path in
                path.move(to: CGPoint(x: 86, y: metrics.heroSize * 0.34))
                path.addCurve(
                    to: CGPoint(x: metrics.heroSize - 84, y: metrics.heroSize * 0.68),
                    control1: CGPoint(x: metrics.heroSize * 0.32, y: metrics.heroSize * 0.08),
                    control2: CGPoint(x: metrics.heroSize * 0.64, y: metrics.heroSize * 0.92)
                )
            }
            .stroke(
                Color.white.opacity(0.3),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 14])
            )
            .frame(width: metrics.heroSize, height: metrics.heroSize)
            .overlay {
                scanRibbon(metrics: metrics)
            }

            magicBurst
                .frame(width: metrics.heroSize, height: metrics.heroSize)

            paperCard(metrics: metrics)
                .offset(x: -metrics.heroSize * 0.22, y: -metrics.heroSize * 0.10)
                .rotationEffect(.degrees(-11))
                .rotationEffect(.degrees(tiltWorld ? -1.5 : 1.5))
                .animation(floatAnimation(duration: 5.8), value: tiltWorld)

            cameraOrb(metrics: metrics)
                .offset(x: 0, y: metrics.heroSize * 0.06)
                .scaleEffect(tiltWorld ? 1.0 : 1.05)
                .animation(floatAnimation(duration: 6.2), value: tiltWorld)

            creaturePortal(metrics: metrics)
                .offset(x: metrics.heroSize * 0.22, y: -metrics.heroSize * 0.06)
                .scaleEffect(tiltWorld ? 1.03 : 0.98)
                .rotationEffect(.degrees(tiltWorld ? 1.6 : -1.6))
                .animation(floatAnimation(duration: 5.1), value: tiltWorld)

            orbitSticker(metrics: metrics)
                .offset(x: metrics.heroSize * 0.30, y: metrics.heroSize * 0.28)
        }
        .frame(height: metrics.heroSize * 0.96)
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 18)
    }

    private var magicBurst: some View {
        ZStack {
            ForEach(Array(burstRays.enumerated()), id: \.offset) { index, ray in
                Capsule()
                    .fill(ray.color.opacity(0.9))
                    .frame(width: 8, height: ray.length)
                    .offset(y: -ray.distance)
                    .rotationEffect(.degrees(ray.angle))
                    .opacity(reduceMotion ? 0.55 : 0.9)
                    .scaleEffect(showHero ? 1 : 0.4)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) :
                            .spring(duration: 0.82, bounce: 0.34).delay(Double(index) * 0.04),
                        value: showHero
                    )
            }
        }
    }

    private func paperCard(metrics: OnboardingMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(red: 0.96, green: 0.97, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color(red: 0.79, green: 0.84, blue: 0.96), lineWidth: 1.5)

            VStack(alignment: .leading, spacing: 14) {
                Text("Draw")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.38))

                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.97, green: 0.98, blue: 1.0))

                    doodleCreature
                        .padding(20)
                }
                .frame(height: 132)

                HStack(spacing: 8) {
                    capsuleTag("Big lines", color: Color(red: 1.0, green: 0.75, blue: 0.43))
                    capsuleTag("Bold shapes", color: Color(red: 0.50, green: 0.88, blue: 0.84))
                }
            }
            .padding(20)
        }
        .frame(width: metrics.cardWidth, height: metrics.cardHeight)
        .shadow(color: Color.black.opacity(0.14), radius: 18, x: 0, y: 12)
    }

    private var doodleCreature: some View {
        ZStack {
            DoodleBlobShape()
                .stroke(Color(red: 0.98, green: 0.48, blue: 0.26), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))

            Path { path in
                path.move(to: CGPoint(x: 28, y: 42))
                path.addCurve(to: CGPoint(x: 98, y: 62), control1: CGPoint(x: 50, y: 18), control2: CGPoint(x: 80, y: 22))
                path.addCurve(to: CGPoint(x: 116, y: 104), control1: CGPoint(x: 122, y: 74), control2: CGPoint(x: 124, y: 92))
            }
            .stroke(Color(red: 0.14, green: 0.70, blue: 0.88), style: StrokeStyle(lineWidth: 7, lineCap: .round))

            HStack(spacing: 20) {
                Circle().fill(Color(red: 0.18, green: 0.24, blue: 0.37)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.18, green: 0.24, blue: 0.37)).frame(width: 12, height: 12)
            }
            .offset(x: -2, y: -6)

            Capsule()
                .fill(Color(red: 0.18, green: 0.24, blue: 0.37))
                .frame(width: 34, height: 8)
                .offset(y: 24)
        }
        .frame(width: 150, height: 126)
    }

    private func cameraOrb(metrics: OnboardingMetrics) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.50, green: 0.98, blue: 0.91),
                            Color(red: 0.08, green: 0.53, blue: 0.82)
                        ],
                        center: .center,
                        startRadius: 12,
                        endRadius: 92
                    )
                )
                .frame(width: metrics.orbSize, height: metrics.orbSize)

            Circle()
                .stroke(Color.white.opacity(0.36), lineWidth: 2)
                .frame(width: metrics.orbSize * 0.82, height: metrics.orbSize * 0.82)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: metrics.orbSize * 0.58, height: metrics.orbSize * 0.58)
                .blur(radius: 3)
                .scaleEffect(orbBreathing ? 1.06 : 0.92)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) :
                        .timingCurve(0.32, 0.02, 0.18, 1, duration: 2.2)
                        .repeatForever(autoreverses: true),
                    value: orbBreathing
                )

            Image(systemName: "viewfinder")
                .font(.system(size: metrics.orbSize * 0.28, weight: .black))
                .foregroundStyle(.white)
                .modifier(ViewfinderPulseModifier(isReducedMotion: reduceMotion, isActive: showHero))

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 10)
                .frame(width: metrics.orbSize * 1.18, height: metrics.orbSize * 1.18)
                .scaleEffect(showHero ? 1.04 : 0.84)
                .opacity(showHero ? 0.65 : 0.22)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) :
                        .easeInOut(duration: 2.6).repeatForever(autoreverses: true),
                    value: showHero
                )

            Circle()
                .trim(from: 0.08, to: 0.24)
                .stroke(Color.white.opacity(0.52), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: metrics.orbSize * 1.36, height: metrics.orbSize * 1.36)
                .rotationEffect(.degrees(orbBreathing ? 190 : -20))
                .opacity(showHero ? 0.9 : 0)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) :
                        .timingCurve(0.34, 0.01, 0.26, 1, duration: 3.4)
                        .repeatForever(autoreverses: false),
                    value: orbBreathing
                )
        }
        .shadow(color: Color(red: 0.10, green: 0.62, blue: 0.83).opacity(0.34), radius: 18, x: 0, y: 10)
    }

    private func creaturePortal(metrics: OnboardingMetrics) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.84, blue: 0.44),
                            Color(red: 1.0, green: 0.58, blue: 0.24),
                            Color(red: 0.98, green: 0.33, blue: 0.39)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: metrics.portalSize, height: metrics.portalSize)

            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: metrics.portalSize * 0.78, height: metrics.portalSize * 0.78)
                .scaleEffect(portalBreathing ? 0.96 : 1.06)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.18) :
                        .timingCurve(0.32, 0.02, 0.18, 1, duration: 2.1)
                        .repeatForever(autoreverses: true),
                    value: portalBreathing
                )

            VStack(spacing: 8) {
                BlobBurstGlyph()
                    .fill(Color.white)
                    .frame(width: metrics.portalSize * 0.22, height: metrics.portalSize * 0.22)
                    .rotationEffect(.degrees(portalBreathing ? -10 : 8))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) :
                            .timingCurve(0.3, 0.0, 0.18, 1, duration: 2.0)
                            .repeatForever(autoreverses: true),
                        value: portalBreathing
                    )

                Text("Alive!")
                    .font(.system(size: metrics.portalLabelSize, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 8, height: 8)
                    .offset(y: -metrics.portalSize * 0.52)
                    .rotationEffect(.degrees(Double(index) * 90))
                    .scaleEffect(showHero ? 1.0 : 0.1)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.18) :
                            .spring(duration: 0.8, bounce: 0.42).delay(Double(index) * 0.05),
                        value: showHero
                    )
            }
        }
        .shadow(color: Color(red: 1.0, green: 0.58, blue: 0.24).opacity(0.32), radius: 22, x: 0, y: 12)
    }

    private func ctaSection(metrics: OnboardingMetrics) -> some View {
        VStack(spacing: 14) {
            Button(action: beginExperience) {
                HStack(spacing: 12) {
                    Text("Make Magic")
                    DoodleLoopIcon()
                        .stroke(Color(red: 0.11, green: 0.14, blue: 0.24), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                        .frame(width: metrics.ctaIconSize, height: metrics.ctaIconSize)
                        .rotationEffect(.degrees(pulseCTA ? 5 : -5))
                        .scaleEffect(pulseCTA ? 1.04 : 0.94)
                }
                .font(.system(size: metrics.ctaFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.14, blue: 0.24))
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.ctaVerticalPadding)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.95, blue: 0.67),
                                        Color(red: 1.0, green: 0.81, blue: 0.36),
                                        Color(red: 1.0, green: 0.61, blue: 0.26)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.44), lineWidth: 1.2)

                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(0.12),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .rotationEffect(.degrees(8))
                            .offset(x: shimmerCTA && !reduceMotion ? 260 : -260)
                            .blendMode(.screen)
                            .animation(
                                reduceMotion ? .none :
                                    .linear(duration: 2.4).repeatForever(autoreverses: false),
                                value: shimmerCTA
                            )

                        Circle()
                            .fill(Color.white.opacity(0.26))
                            .frame(width: 90, height: 90)
                            .blur(radius: 12)
                            .offset(x: isPressingCTA ? -60 : 56, y: isPressingCTA ? -10 : 10)
                            .animation(reduceMotion ? .easeOut(duration: 0.14) : .timingCurve(0.18, 0.84, 0.24, 1, duration: 0.28), value: isPressingCTA)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(buttonScale)
            .rotationEffect(.degrees(isPressingCTA ? -0.6 : 0))
            .shadow(color: Color(red: 1.0, green: 0.66, blue: 0.22).opacity(isPressingCTA ? 0.38 : 0.28), radius: isPressingCTA ? 28 : 22, x: 0, y: isPressingCTA ? 18 : 14)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.2, 0.82, 0.24, 1, duration: 0.22), value: isPressingCTA)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.32, 0.02, 0.18, 1, duration: 2.0).repeatForever(autoreverses: true), value: pulseCTA)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        handleCTAChanged()
                    }
                    .onEnded { _ in
                        isPressingCTA = false
                    }
            )
            .disabled(isExiting)

            Text("Point the iPad at your drawing and watch it pop into the room.")
                .font(.system(size: metrics.ctaFootnoteSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
        .frame(maxWidth: metrics.ctaWidth)
    }

    private func flowToken(title: String, tint: Color, angle: Double, metrics: OnboardingMetrics) -> some View {
        Text(title)
            .font(.system(size: metrics.useSplitLayout ? 20 : 17, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, metrics.useSplitLayout ? 18 : 15)
            .padding(.vertical, metrics.useSplitLayout ? 12 : 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .overlay {
                        Capsule()
                            .fill(tint.opacity(0.22))
                        Capsule()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    }
            )
            .rotationEffect(.degrees(angle))
            .offset(y: tokenDrift ? -4 : 5)
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
            .animation(
                reduceMotion ? .easeOut(duration: 0.18) :
                    .timingCurve(0.28, 0.0, 0.2, 1, duration: 2.6)
                    .repeatForever(autoreverses: true),
                value: tokenDrift
            )
    }

    private var transitionGlow: some View {
        Rectangle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.68),
                        Color(red: 1.0, green: 0.84, blue: 0.53).opacity(0.34),
                        .clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 520
                )
            )
            .ignoresSafeArea()
            .overlay {
                if !reduceMotion {
                    Circle()
                        .stroke(Color.white.opacity(0.38), lineWidth: 32)
                        .scaleEffect(isExiting ? 1.26 : 0.2)
                        .opacity(isExiting ? 0 : 0.55)
                        .blur(radius: 10)
                }
            }
    }

    private var buttonScale: CGFloat {
        if isExiting { return 1.1 }
        if isPressingCTA { return 0.965 }
        if reduceMotion { return 1.0 }
        return pulseCTA ? 1.015 : 0.985
    }

    private func beginExperience() {
        guard !isExiting else { return }
        isPressingCTA = false
        launchFeedbackTick += 1

        if reduceMotion {
            isExiting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                onContinue()
            }
            return
        }

        withAnimation(.timingCurve(0.14, 0.82, 0.24, 1, duration: 0.46)) {
            isExiting = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            onContinue()
        }
    }

    private func runEntranceSequence() {
        tiltWorld = true
        beamSweep = true
        entranceSpark = true
        pulseCTA = true
        shimmerCTA = true
        orbBreathing = true
        portalBreathing = true
        tokenDrift = true

        if reduceMotion {
            showHeadline = true
            showHero = true
            showStory = true
            showCTA = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(entranceAnimation(duration: 0.64)) {
                showHeadline = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(entranceAnimation(duration: 0.9)) {
                showHero = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(entranceAnimation(duration: 0.74)) {
                showStory = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            withAnimation(entranceAnimation(duration: 0.7)) {
                showCTA = true
            }
        }
    }

    private func handleCTAChanged() {
        guard !isPressingCTA else { return }
        isPressingCTA = true
        pressFeedbackTick += 1
    }

    private func entranceAnimation(duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .timingCurve(0.17, 0.9, 0.21, 1, duration: duration)
    }

    private func capsuleTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.18, green: 0.23, blue: 0.38))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.82))
            .clipShape(Capsule())
    }

    private func floatAnimation(duration: Double) -> Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .easeInOut(duration: duration).repeatForever(autoreverses: true)
    }

    private func scanRibbon(metrics: OnboardingMetrics) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.32),
                        Color(red: 0.53, green: 0.95, blue: 0.90).opacity(0.48),
                        Color.white.opacity(0.0),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 42, height: metrics.heroSize * 0.76)
            .blur(radius: 2)
            .rotationEffect(.degrees(22))
            .offset(x: beamSweep && showHero && !reduceMotion ? metrics.heroSize * 0.16 : -metrics.heroSize * 0.18)
            .opacity(showHero ? 0.9 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.18) :
                    .timingCurve(0.34, 0.01, 0.18, 1, duration: 1.6)
                    .repeatForever(autoreverses: true),
                value: beamSweep
            )
    }

    private func orbitSticker(metrics: OnboardingMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.13, green: 0.18, blue: 0.34).opacity(0.86))
                .frame(width: metrics.useSplitLayout ? 108 : 92, height: metrics.useSplitLayout ? 92 : 78)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            VStack(spacing: 6) {
                Text("WOW")
                    .font(.system(size: metrics.useSplitLayout ? 26 : 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.46))
                Text("magic")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
        .rotationEffect(.degrees(tiltWorld ? 7 : 2))
        .scaleEffect(showHero ? (tiltWorld ? 1.04 : 0.97) : 0.5)
        .opacity(showHero ? 1 : 0)
        .animation(floatAnimation(duration: 6.6), value: tiltWorld)
    }

    private func cometTrail(metrics: OnboardingMetrics) -> some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.24),
                            Color(red: 1.0, green: 0.85, blue: 0.52).opacity(0.9)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: metrics.useSplitLayout ? 180 : 130, height: 18)
                .rotationEffect(.degrees(-18))

            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .offset(x: metrics.useSplitLayout ? 74 : 50, y: -6)
                .shadow(color: Color.white.opacity(0.6), radius: 14, x: 0, y: 0)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

// MARK: - Metrics

private struct OnboardingMetrics {
    let size: CGSize

    var useSplitLayout: Bool { size.width >= 900 }
    var contentWidth: CGFloat { min(useSplitLayout ? 1180 : 720, size.width - 32) }
    var horizontalPadding: CGFloat { useSplitLayout ? 28 : 18 }
    var topPadding: CGFloat { useSplitLayout ? 36 : 24 }
    var bottomPadding: CGFloat { useSplitLayout ? 34 : 24 }
    var sectionSpacing: CGFloat { useSplitLayout ? 34 : 26 }
    var titleFontSize: CGFloat { useSplitLayout ? 62 : (size.width > 420 ? 46 : 40) }
    var titleLineSpacing: CGFloat { useSplitLayout ? 4 : 2 }
    var subtitleFontSize: CGFloat { useSplitLayout ? 24 : 18 }
    var heroSize: CGFloat { useSplitLayout ? min(560, size.width * 0.44) : min(420, size.width - 36) }
    var heroCornerRadius: CGFloat { useSplitLayout ? 42 : 34 }
    var cardWidth: CGFloat { useSplitLayout ? 250 : 214 }
    var cardHeight: CGFloat { useSplitLayout ? 258 : 230 }
    var orbSize: CGFloat { useSplitLayout ? 148 : 126 }
    var portalSize: CGFloat { useSplitLayout ? 156 : 132 }
    var portalLabelSize: CGFloat { useSplitLayout ? 28 : 24 }
    var storyCardPadding: CGFloat { useSplitLayout ? 28 : 22 }
    var storyTitleSize: CGFloat { useSplitLayout ? 28 : 24 }
    var storyFootnoteSize: CGFloat { useSplitLayout ? 17 : 15 }
    var stepIconSize: CGFloat { useSplitLayout ? 60 : 52 }
    var stepTitleSize: CGFloat { useSplitLayout ? 22 : 19 }
    var stepBodySize: CGFloat { useSplitLayout ? 17 : 15 }
    var ctaWidth: CGFloat { useSplitLayout ? 540 : min(560, size.width - 36) }
    var ctaFontSize: CGFloat { useSplitLayout ? 28 : 24 }
    var ctaIconSize: CGFloat { useSplitLayout ? 28 : 24 }
    var ctaVerticalPadding: CGFloat { useSplitLayout ? 24 : 20 }
    var ctaFootnoteSize: CGFloat { useSplitLayout ? 16 : 14 }
}

// MARK: - Supporting Types

private struct StarSpec {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let expandedScale: CGFloat
    let duration: Double
    let color: Color
}

private struct BurstRay {
    let angle: Double
    let length: CGFloat
    let distance: CGFloat
    let color: Color
}

// MARK: - Data

private let stars: [StarSpec] = [
    StarSpec(x: 0.10, y: 0.12, size: 6, opacity: 0.78, expandedScale: 1.22, duration: 3.0, color: .white),
    StarSpec(x: 0.20, y: 0.26, size: 9, opacity: 0.92, expandedScale: 1.3, duration: 2.6, color: Color(red: 1.0, green: 0.87, blue: 0.56)),
    StarSpec(x: 0.83, y: 0.14, size: 8, opacity: 0.82, expandedScale: 1.25, duration: 3.4, color: .white),
    StarSpec(x: 0.76, y: 0.28, size: 7, opacity: 0.74, expandedScale: 1.18, duration: 2.9, color: Color(red: 0.56, green: 0.94, blue: 0.86)),
    StarSpec(x: 0.14, y: 0.62, size: 7, opacity: 0.70, expandedScale: 1.18, duration: 2.8, color: .white),
    StarSpec(x: 0.91, y: 0.72, size: 10, opacity: 0.88, expandedScale: 1.3, duration: 3.1, color: Color(red: 1.0, green: 0.81, blue: 0.40)),
    StarSpec(x: 0.52, y: 0.10, size: 6, opacity: 0.68, expandedScale: 1.15, duration: 2.5, color: .white),
    StarSpec(x: 0.58, y: 0.82, size: 8, opacity: 0.78, expandedScale: 1.22, duration: 3.3, color: Color(red: 0.59, green: 0.78, blue: 1.0)),
    StarSpec(x: 0.32, y: 0.84, size: 5, opacity: 0.62, expandedScale: 1.14, duration: 2.7, color: .white)
]

private let burstRays: [BurstRay] = [
    BurstRay(angle: -24, length: 72, distance: 82, color: Color.white.opacity(0.9)),
    BurstRay(angle: 12, length: 58, distance: 74, color: Color(red: 1.0, green: 0.82, blue: 0.42)),
    BurstRay(angle: 78, length: 48, distance: 72, color: Color(red: 0.57, green: 0.94, blue: 0.88)),
    BurstRay(angle: 140, length: 44, distance: 78, color: Color.white.opacity(0.84)),
    BurstRay(angle: 202, length: 56, distance: 84, color: Color(red: 1.0, green: 0.62, blue: 0.34)),
    BurstRay(angle: 258, length: 50, distance: 76, color: Color(red: 0.57, green: 0.77, blue: 1.0))
]

// MARK: - Shapes

private struct DoodleBlobShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.54))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.22),
            control1: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.34),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.26),
            control2: CGPoint(x: rect.minX + rect.width * 0.50, y: rect.minY + rect.height * 0.06)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.46),
            control1: CGPoint(x: rect.minX + rect.width * 0.77, y: rect.minY + rect.height * 0.24),
            control2: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.82),
            control1: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.minY + rect.height * 0.66),
            control2: CGPoint(x: rect.minX + rect.width * 0.90, y: rect.minY + rect.height * 0.88)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.76),
            control1: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.74),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.92)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.54),
            control1: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.70),
            control2: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.66)
        )

        return path
    }
}

private struct ViewfinderPulseModifier: ViewModifier {
    let isReducedMotion: Bool
    let isActive: Bool

    func body(content: Content) -> some View {
        if isReducedMotion {
            content
        } else {
            content.symbolEffect(.pulse.byLayer, options: .repeating, value: isActive)
        }
    }
}

private struct DoodleLoopIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.30),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.14, y: rect.midY),
            control1: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.40)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18),
            control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.maxY - rect.height * 0.10),
            control2: CGPoint(x: rect.maxX - rect.width * 0.42, y: rect.maxY - rect.height * 0.12)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.22),
            control2: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY - rect.height * 0.02)
        )
        path.move(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.28))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.38))
        return path
    }
}

private struct BlobBurstGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        path.addEllipse(in: CGRect(x: c.x - rect.width * 0.12, y: c.y - rect.height * 0.30, width: rect.width * 0.24, height: rect.height * 0.28))
        path.addEllipse(in: CGRect(x: c.x - rect.width * 0.34, y: c.y - rect.height * 0.10, width: rect.width * 0.26, height: rect.height * 0.22))
        path.addEllipse(in: CGRect(x: c.x + rect.width * 0.08, y: c.y - rect.height * 0.08, width: rect.width * 0.28, height: rect.height * 0.24))
        path.addEllipse(in: CGRect(x: c.x - rect.width * 0.10, y: c.y + rect.height * 0.06, width: rect.width * 0.20, height: rect.height * 0.22))
        return path
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
