import SwiftUI

struct AppRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            LibraryRootView()
                .opacity(showSplash ? 0 : 1)
                .animation(.easeInOut(duration: 0.35), value: showSplash)

            if showSplash {
                LaunchSplashView {
                    withAnimation {
                        showSplash = false
                    }
                }
            }
        }
    }
}

private struct LaunchSplashView: View {
    let onFinish: () -> Void
    @State private var glowOpacity: CGFloat = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var toolbarOpacity: CGFloat = 0
    @State private var backgroundShift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: backgroundShift ? splashGradient2 : splashGradient1,
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: backgroundShift)

            StarFieldView(count: 70,
                          sizeRange: 1...2.5,
                          opacityRange: 0.15...0.6,
                          twinkleRange: 0.3...0.8,
                          driftRange: -8...8)

            StarFieldView(count: 18,
                          sizeRange: 3...6.5,
                          opacityRange: 0.25...0.9,
                          twinkleRange: 0.5...1.0,
                          driftRange: -18...18)

            Image(systemName: "lasso.and.sparkles")
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.orange.opacity(0.4), radius: 12, y: 8)
                .scaleEffect(logoScale)
                .opacity(Double(logoScale))
                .animation(.spring(response: 0.65, dampingFraction: 0.75), value: logoScale)

            Circle()
                .fill(Color.orange.opacity(0.25))
                .frame(width: 180)
                .blur(radius: 30)
                .scaleEffect(1.15)
                .opacity(glowOpacity)
                .animation(.easeInOut(duration: 0.6), value: glowOpacity)

            VStack {
                Spacer()
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 220, height: 42)
                    .overlay(
                        HStack(spacing: 14) {
                            Image(systemName: "scribble.variable")
                            Image(systemName: "hand.draw")
                            Image(systemName: "wand.and.stars")
                        }
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    )
                    .opacity(Double(toolbarOpacity))
                Spacer().frame(height: 90)
            }
        }
        .task {
            animateSequence()
        }
}
private struct StarFieldView: View {
    struct Star: Identifiable {
        let id = UUID()
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let minOpacity: Double
        let maxOpacity: Double
        let twinkleDuration: Double
        let twinkleDelay: Double
        let driftX: CGFloat
        let driftY: CGFloat
        let driftDuration: Double
        let hue: Double
    }

    let stars: [Star]
    @State private var twinklePhase = false
    @State private var driftPhase: CGFloat = -1

    init(count: Int,
         sizeRange: ClosedRange<CGFloat>,
         opacityRange: ClosedRange<Double>,
         twinkleRange: ClosedRange<Double>,
         driftRange: ClosedRange<CGFloat>) {
        var generated: [Star] = []
        for _ in 0..<count {
            let star = Star(x: CGFloat.random(in: 0...1),
                            y: CGFloat.random(in: 0...1),
                            size: CGFloat.random(in: sizeRange),
                            minOpacity: opacityRange.lowerBound,
                            maxOpacity: opacityRange.upperBound,
                            twinkleDuration: Double.random(in: twinkleRange),
                            twinkleDelay: Double.random(in: 0...0.6),
                            driftX: CGFloat.random(in: driftRange),
                            driftY: CGFloat.random(in: driftRange),
                            driftDuration: Double.random(in: 3...5.5),
                            hue: Double.random(in: 0.04...0.12))
            generated.append(star)
        }
        self.stars = generated
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                Circle()
                    .fill(Color(hue: star.hue, saturation: 0.45, brightness: 1.0))
                    .frame(width: star.size, height: star.size)
                    .position(x: starPosition(star: star, axis: .x, maxLength: geo.size.width),
                              y: starPosition(star: star, axis: .y, maxLength: geo.size.height))
                    .opacity(twinklePhase ? star.maxOpacity : star.minOpacity)
                    .blur(radius: star.size * 0.35)
                    .animation(Animation.easeInOut(duration: star.twinkleDuration)
                                .repeatForever(autoreverses: true)
                                .delay(star.twinkleDelay),
                               value: twinklePhase)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            twinklePhase = true
            withAnimation(Animation.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                driftPhase = 1
            }
        }
    }

    private enum Axis { case x, y }

    private func starPosition(star: Star, axis: Axis, maxLength: CGFloat) -> CGFloat {
        switch axis {
        case .x:
            return star.x * maxLength + star.driftX * driftPhase
        case .y:
            return star.y * maxLength + star.driftY * driftPhase
        }
    }
}
    private func animateSequence() {
        glowOpacity = 0
        logoScale = 0.85
        toolbarOpacity = 0
        backgroundShift = false

        withAnimation(.easeInOut(duration: 0.8)) {
            glowOpacity = 1
            backgroundShift = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                logoScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 0.4)) {
                toolbarOpacity = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            onFinish()
        }
    }

    private var splashGradient1: [Color] {
        [Color(red: 0.11, green: 0.09, blue: 0.18),
         Color(red: 0.24, green: 0.19, blue: 0.28)]
    }

    private var splashGradient2: [Color] {
        [Color(red: 0.37, green: 0.3, blue: 0.24),
         Color(red: 0.97, green: 0.95, blue: 0.87)]
    }
}
