//
//  ClipboardWidget.swift
//  boringNotch
//

import KeyboardShortcuts
import SwiftUI

/// Panel-only clipboard history. Like the shelf it has no foreground
/// activity, so it never claims the wings.
///
/// Opt-in (disabled by default): monitoring reads the general pasteboard
/// programmatically, which recent macOS can gate behind a privacy prompt.
@MainActor
final class ClipboardWidget: NotchWidget {
    static let widgetID = "clipboard"

    let id = ClipboardWidget.widgetID
    let displayName = "Clipboard"
    let icon = "doc.on.clipboard"
    var isEnabled: Bool = false {
        // Polling runs only while the widget is enabled, not just while the
        // panel shows it — history must catch copies made with the panel closed.
        didSet {
            isEnabled ? ClipboardHistoryStore.shared.startMonitoring()
                      : ClipboardHistoryStore.shared.stopMonitoring()
        }
    }

    /// Unique per the registry's assertion; irrelevant otherwise because
    /// `claimsWings` is always false.
    let wingPriority: Int = 5

    @MainActor
    var claimsWings: Bool { false }

    var widthRange: WidthRange {
        WidthRange(min: ClipboardLayoutTokens.panelMinWidth,
                   ideal: ClipboardLayoutTokens.panelIdealWidth,
                   max: LayoutTokens.panelMaxWidth)
    }

    var heightRange: HeightRange {
        .fixed(ClipboardLayoutTokens.expandedHeight)
    }

    @MainActor
    func makeLeftWingView() -> AnyView {
        AnyView(ClipboardLeftWing())
    }

    @MainActor
    func makeRightWingView() -> AnyView {
        AnyView(ClipboardRightWing())
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(
            ClipboardView()
                .frame(height: ClipboardLayoutTokens.expandedHeight)
        )
    }

    func activate() {}
    func deactivate() {}
}

enum ClipboardLayoutTokens {
    static let panelMinWidth: CGFloat = 480
    static let panelIdealWidth: CGFloat = 560
    static let expandedHeight: CGFloat = 150
    static let cardSize = CGSize(width: 128, height: 104)
    static let cardCornerRadius: CGFloat = 10
    static let compactHorizontalPadding: CGFloat = 10
    static let compactVerticalPadding: CGFloat = 6
}

// MARK: - Expanded

struct ClipboardView: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @StateObject private var quickLook = QuickLookService()

    var body: some View {
        content
            .quickLookPresenter(using: quickLook)
            .environmentObject(quickLook)
            // The panel can't become key, so ⌘C never reaches it. Claim ⌘C
            // globally only while there is a selection to copy, so the
            // frontmost app keeps its own ⌘C the rest of the time.
            .onChange(of: store.selectedIDs.isEmpty) { _, isEmpty in
                isEmpty ? KeyboardShortcuts.disable(.clipboardCopySelection)
                        : KeyboardShortcuts.enable(.clipboardCopySelection)
            }
            .onDisappear {
                store.clearSelection()
                KeyboardShortcuts.disable(.clipboardCopySelection)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Clipboard")
                    .font(TypographyTokens.expandedHeader)
                    .foregroundStyle(ThemeTokens.textPrimary)
                Text("\(store.items.count)")
                    .font(TypographyTokens.expandedCaption)
                    .monospacedDigit()
                    .foregroundStyle(ThemeTokens.textSecondary)
                Spacer()
                if !store.selectedIDs.isEmpty {
                    Button("Copy \(store.selectedIDs.count) (⌘C)") { store.copySelected() }
                        .buttonStyle(.plain)
                        .font(TypographyTokens.expandedSemibold)
                        .foregroundStyle(ThemeTokens.textPrimary)
                }
                if !store.items.isEmpty {
                    Button("Clear") { store.clear() }
                        .buttonStyle(.plain)
                        .font(TypographyTokens.expandedSemibold)
                        .foregroundStyle(ThemeTokens.textSecondary)
                }
            }

            if store.items.isEmpty {
                Text("Copied text, images and files show up here. Click to copy (images open a preview), ⌘-click to pick several and press ⌘C.")
                    .font(TypographyTokens.expandedBodyPlain)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(store.items) { item in
                            ClipboardCard(item: item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @EnvironmentObject private var quickLook: QuickLookService
    @State private var isHovering = false
    @State private var justCopied = false

    private var isSelected: Bool { store.selectedIDs.contains(item.id) }

    var body: some View {
        content
            .frame(width: ClipboardLayoutTokens.cardSize.width,
                   height: ClipboardLayoutTokens.cardSize.height,
                   alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: ClipboardLayoutTokens.cardCornerRadius)
                    .fill(Color.white.opacity(isHovering ? 0.14 : 0.08))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: ClipboardLayoutTokens.cardCornerRadius)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    HStack(spacing: 2) {
                        // Images open a preview on click, so copying one
                        // needs its own control.
                        Button(action: copy) {
                            Image(systemName: "doc.on.doc.fill")
                        }
                        Button {
                            store.remove(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ThemeTokens.textSecondary)
                    .padding(4)
                }
            }
            .overlay {
                if justCopied {
                    RoundedRectangle(cornerRadius: ClipboardLayoutTokens.cardCornerRadius)
                        .fill(Color.black.opacity(0.6))
                        .overlay(
                            Label("Copied", systemImage: "checkmark")
                                .font(TypographyTokens.expandedSemibold)
                                .foregroundStyle(.white)
                        )
                }
            }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture(perform: handleTap)
    }

    private func handleTap() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            store.toggleSelection(item)
        } else if item.kind == .image, let url = store.imageURL(for: item) {
            quickLook.isQuickLookOpen && quickLook.selectedURL == url
                ? quickLook.hide()
                : quickLook.show(urls: [url])
        } else {
            copy()
        }
    }

    private func copy() {
        store.copy(item)
        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            justCopied = false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            // Long clips scroll inside the card rather than being cut off.
            ScrollView(.vertical, showsIndicators: false) {
                Text(item.text ?? "")
                    .font(TypographyTokens.expandedBodyPlain)
                    .foregroundStyle(ThemeTokens.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            }
        case .files:
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.filePaths ?? [], id: \.self) { path in
                        HStack(spacing: 4) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(TypographyTokens.expandedCaption)
                                .foregroundStyle(ThemeTokens.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        }
    }
}

// MARK: - Wings (built for symmetry, never shown: claimsWings is false)

struct ClipboardLeftWing: View {
    var body: some View {
        Image(systemName: "doc.on.clipboard")
            .font(TypographyTokens.compactGlyph)
            .foregroundStyle(ThemeTokens.textSecondary)
            .padding(.horizontal, ClipboardLayoutTokens.compactHorizontalPadding)
            .padding(.vertical, ClipboardLayoutTokens.compactVerticalPadding)
    }
}

struct ClipboardRightWing: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared

    var body: some View {
        Text("\(store.items.count)")
            .font(TypographyTokens.compactTitle)
            .monospacedDigit()
            .foregroundStyle(ThemeTokens.textPrimary)
            .padding(.horizontal, ClipboardLayoutTokens.compactHorizontalPadding)
            .padding(.vertical, ClipboardLayoutTokens.compactVerticalPadding)
    }
}
