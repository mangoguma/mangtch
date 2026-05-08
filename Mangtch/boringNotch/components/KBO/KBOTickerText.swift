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

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    init(_ text: String, font: Font = .body, speed: Double = 21, isActive: Bool = true, oneShot: Bool = false) {
        self.text = text
        self.font = font
        self.speed = speed
        self.isActive = isActive
        self.oneShot = oneShot
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
            let scrollDistance = textWidth - containerWidth
            let duration = scrollDistance / speed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.linear(duration: duration)) {
                    offset = -scrollDistance
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    animating = false
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
