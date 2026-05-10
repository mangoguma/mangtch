import SwiftUI

/// Horizontally-scrolling text for the KBO play ticker. Supports oneShot
/// mode (scrolls to reveal the tail then stops) used by the wing ticker,
/// and looping mode used by music titles.
///
/// Distinct from boring.notch's `MarqueeText` (binding-based, frameWidth)
/// to avoid a naming collision.
struct KBOTickerText: View {
    let text: String
    let font: Font
    let speed: Double
    let isActive: Bool
    let oneShot: Bool
    /// Called once when the oneShot scroll animation completes (or is
    /// skipped because the text fits). Not called in looping mode.
    var onScrollDone: (() -> Void)? = nil

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    init(_ text: String, font: Font = .body, speed: Double = 21, isActive: Bool = true, oneShot: Bool = false, onScrollDone: (() -> Void)? = nil) {
        self.text = text
        self.font = font
        self.speed = speed
        self.isActive = isActive
        self.oneShot = oneShot
        self.onScrollDone = onScrollDone
    }

    private var needsScroll: Bool {
        isActive && textWidth > containerWidth
    }

    var body: some View {
        GeometryReader { geo in
            let _ = updateContainerWidth(geo.size.width)

            if needsScroll {
                HStack(spacing: oneShot ? 0 : 40) {
                    textView
                    if !oneShot { textView }
                }
                .offset(x: offset)
                .onAppear { startAnimation() }
                .onChange(of: text) {
                    offset = 0
                    animating = false
                    startAnimation()
                }
            } else {
                textView
            }
        }
        .frame(height: 14)
        .clipped()
    }

    private var textView: some View {
        Text(text)
            .font(font)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { textWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, w in textWidth = w }
                }
            )
    }

    private func updateContainerWidth(_ w: CGFloat) {
        if containerWidth != w { containerWidth = w }
    }

    private func startAnimation() {
        guard !animating else { return }
        offset = 0
        animating = true

        if oneShot {
            // scrollDistance/duration computed inside the closure so they read
            // @State values AFTER layout measurement — capturing them here
            // would freeze pre-measurement zeroes and produce a zero-distance
            // (text scrolls completely off-screen) animation.
            // containerWidth guard prevents over-scroll when measurement hasn't
            // arrived yet; onChange(of: containerWidth) retries in that case.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let scrollDistance = textWidth - containerWidth
                guard scrollDistance > 0 else {
                    animating = false
                    onScrollDone?()
                    return
                }
                // In oneShot (KBO play ticker) mode, match scroll duration to
                // estimated Korean TTS duration so text and speech end together.
                // Empirical rate for ko-KR Yuna at default AVSpeechUtteranceDefaultSpeechRate:
                // ~8 characters/second. Falls back to scrollDistance/speed for
                // very short or empty strings.
                let ttsDuration = Double(text.count) / 8.0
                let duration = max(ttsDuration, 0.4)
                withAnimation(.linear(duration: duration)) {
                    offset = -scrollDistance
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    animating = false
                    onScrollDone?()
                }
            }
        } else {
            let scrollDistance = textWidth + 40
            let duration = scrollDistance / speed
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.linear(duration: duration)) {
                    offset = -scrollDistance
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) {
                    offset = 0
                    animating = false
                    startAnimation()
                }
            }
        }
    }
}
