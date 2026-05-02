import SwiftUI

struct MarqueeText: View {
    let text: String
    let font: Font
    let speed: Double // points per second
    let isActive: Bool

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animating = false

    init(_ text: String, font: Font = .body, speed: Double = 21, isActive: Bool = true) {
        self.text = text
        self.font = font
        self.speed = speed
        self.isActive = isActive
    }

    private var needsScroll: Bool {
        isActive && textWidth > containerWidth && containerWidth > 0
    }

    var body: some View {
        if !isActive {
            // Static truncated text with ellipsis
            Text(text)
                .font(font)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            GeometryReader { geo in
                let _ = updateContainerWidth(geo.size.width)

                if needsScroll {
                    HStack(spacing: 40) {
                        textView
                        textView
                    }
                    .offset(x: offset)
                    .onAppear { startAnimation() }
                    .onChange(of: text) {
                        resetAnimation()
                    }
                } else {
                    textView
                }
            }
            .frame(height: textHeight)
            .clipped()
            .onChange(of: isActive) {
                if isActive && needsScroll && !animating {
                    startAnimation()
                } else if !isActive {
                    offset = 0
                    animating = false
                }
            }
        }
    }

    private var textView: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: TextWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(TextWidthKey.self) { width in
                textWidth = width
            }
    }

    private var textHeight: CGFloat {
        // Approximate single-line height based on font
        16
    }

    private func updateContainerWidth(_ width: CGFloat) {
        if containerWidth != width {
            DispatchQueue.main.async {
                containerWidth = width
                if needsScroll && !animating {
                    startAnimation()
                }
            }
        }
    }

    private func startAnimation() {
        guard needsScroll else { return }
        offset = 0
        animating = true

        // Distance to scroll: one full text width + gap
        let scrollDistance = textWidth + 40
        let duration = scrollDistance / speed

        // Pause at start, then scroll
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.linear(duration: duration)) {
                offset = -scrollDistance
            }

            // Reset and repeat
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 1.0) {
                offset = 0
                animating = false
                startAnimation()
            }
        }
    }

    private func resetAnimation() {
        offset = 0
        animating = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            startAnimation()
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
