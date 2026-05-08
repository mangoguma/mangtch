import SwiftUI

/// Segmented icon row at the top of the expanded panel that lets the user
/// flip between enabled widgets. Hides itself when there's at most one
/// widget enabled, since a single-tab control would just be visual noise.
///
/// Note this controls **panel content only** — the wings are owned by the
/// priority chain (see `BoringViewModel.wingOwnerID`) and aren't affected
/// by switcher selection. Decoupling lets the user park on a specific
/// widget's expanded view without yanking the wings around.
struct WidgetSwitcherBar: View {
    /// Caller passes the snapshot of enabled widgets — observation lives in
    /// the parent (which holds the @State on the @Observable registry).
    let widgets: [AnyNotchWidget]
    @Binding var currentID: String

    var body: some View {
        if widgets.count > 1 {
            HStack(spacing: 6) {
                ForEach(widgets) { widget in
                    Button {
                        withAnimation(AnimationTokens.expandClick) {
                            currentID = widget.id
                        }
                    } label: {
                        Image(systemName: widget.icon)
                            .font(TypographyTokens.switcherIcon)
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(currentID == widget.id
                                          ? ThemeTokens.switcherSelectedFill
                                          : Color.clear)
                            )
                            .foregroundStyle(currentID == widget.id ? .primary : .secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(widget.displayName)
                }
            }
            .padding(.vertical, 3)
        }
    }
}
