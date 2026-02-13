import SwiftUI

struct AudioVisualizerView: View {
    let isPlaying: Bool

    @State private var barHeights: [CGFloat] = [0.15, 0.15, 0.15, 0.15, 0.15]
    @State private var displayLinkID: UUID?
    @State private var accumulatedTime: TimeInterval = 0

    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 16

    /// Interval between bar height randomizations (~6.7 Hz, matching original Timer).
    /// The DisplayLink fires at 60fps but we only update bar targets at this cadence
    /// so spring animations have time to interpolate smoothly.
    private let randomizeInterval: TimeInterval = 0.15

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(.primary.opacity(0.7))
                    .frame(width: barWidth, height: barHeights[index] * maxHeight)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.5),
                        value: barHeights[index]
                    )
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .onAppear {
            setupDisplayLink()
        }
        .onDisappear {
            tearDownDisplayLink()
        }
        .onChange(of: isPlaying) { _, newValue in
            if !newValue {
                // Set to low static height when not playing
                withAnimation(.easeOut(duration: 0.5)) {
                    barHeights = barHeights.map { _ in 0.15 }
                }
            }
            setupDisplayLink()
        }
    }

    private func setupDisplayLink() {
        tearDownDisplayLink()

        if isPlaying {
            accumulatedTime = 0
            displayLinkID = DisplayLinkManager.shared.subscribe { [self] deltaTime in
                accumulatedTime += deltaTime
                if accumulatedTime >= randomizeInterval {
                    accumulatedTime -= randomizeInterval
                    randomizeHeights()
                }
            }
        }
    }

    private func tearDownDisplayLink() {
        if let id = displayLinkID {
            DisplayLinkManager.shared.unsubscribe(id)
            displayLinkID = nil
        }
    }

    private func randomizeHeights() {
        barHeights = (0..<barCount).map { _ in
            CGFloat.random(in: 0.15...1.0)
        }
    }
}
