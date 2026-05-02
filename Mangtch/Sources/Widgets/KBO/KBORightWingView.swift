import SwiftUI

/// Right-wing view used while the KBO widget is the active selection
/// and a live game is pinned. Renders the latest play as a TV-news
/// ticker over the top of whatever's underneath, and on hover swaps to
/// two toggle buttons — one for the ticker itself, one for `say` TTS —
/// so the user can mute either without diving into Settings.
struct KBORightWingView: View {
    @Bindable var viewModel: KBOViewModel
    private var notchVM: NotchViewModel { NotchViewModel.shared }

    var body: some View {
        let isHovering = notchVM.hoveredWing == .right
        ZStack {
            Group {
                if let play = viewModel.latestPlayText {
                    tickerText(play)
                } else {
                    idlePlaceholder
                }
            }
            .opacity(isHovering ? 0 : 1)
            .allowsHitTesting(!isHovering)

            hoverControls
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    // MARK: - Layers

    private func tickerText(_ text: String) -> some View {
        // Two-line allowance so a long play description can wrap
        // gracefully at wing-width without being chopped.
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idlePlaceholder: some View {
        HStack(spacing: 4) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(viewModel.tickerEnabled ? "중계 대기 중" : "중계 꺼짐")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hoverControls: some View {
        HStack(spacing: 6) {
            toggleButton(
                isOn: viewModel.tickerEnabled,
                onIcon: "captions.bubble.fill",
                offIcon: "captions.bubble",
                label: viewModel.tickerEnabled ? "중계 끄기" : "중계 켜기"
            ) {
                viewModel.tickerEnabled.toggle()
            }

            toggleButton(
                isOn: viewModel.ttsEnabled,
                onIcon: "speaker.wave.2.fill",
                offIcon: "speaker.slash.fill",
                label: viewModel.ttsEnabled ? "음성 끄기" : "음성 켜기"
            ) {
                viewModel.ttsEnabled.toggle()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func toggleButton(
        isOn: Bool,
        onIcon: String,
        offIcon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        // onTapGesture for the same reason as music wing — SwiftUI Button
        // doesn't fire while the panel is non-key.
        Image(systemName: isOn ? onIcon : offIcon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 22)
            .contentShape(Rectangle())
            .onTapGesture { action() }
            .help(label)
    }
}
