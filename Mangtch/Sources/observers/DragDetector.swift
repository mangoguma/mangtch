import AppKit
import UniformTypeIdentifiers

/// Watches for a system-wide file drag and surfaces the FileShelf as soon
/// as the cursor enters the notch's hit zone.
///
/// Uses pasteboard polling instead of global mouse monitors — macOS 26
/// doesn't reliably deliver leftMouseDragged to global monitors during
/// cross-app file drags. Polling the drag pasteboard's changeCount at
/// 20Hz is lightweight and catches drags from any app.
@MainActor
final class DragDetector {
    static let shared = DragDetector()

    private var pollTimer: Timer?
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var lastChangeCount = 0
    private var insideNotchHotzone = false

    private init() {}

    func start() {
        stop()
        lastChangeCount = dragPasteboard.changeCount
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        insideNotchHotzone = false
    }

    private func poll() {
        let current = dragPasteboard.changeCount
        // Pasteboard changed → a drag started or updated
        if current != lastChangeCount {
            lastChangeCount = current
            // Verify it contains droppable content
            guard hasShelfCompatibleContent() else { return }
        }

        // Check if a drag with compatible content is active by seeing
        // if the pasteboard still has file URLs. Once the drag ends,
        // the pasteboard may clear or the mouse button is up — we
        // detect "drag ended" when the cursor leaves the hotzone.
        guard hasShelfCompatibleContent() else {
            if insideNotchHotzone {
                insideNotchHotzone = false
            }
            return
        }

        let cursor = NSEvent.mouseLocation
        // Only check hotzone while the mouse is pressed (dragging).
        // NSEvent.pressedMouseButtons bit 0 = left button.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            if insideNotchHotzone {
                insideNotchHotzone = false
            }
            return
        }

        let targetWindow = NotchWindowManager.shared.window(under: cursor)
        let inHotzone = (targetWindow != nil) && isInsideNotchHotzone(cursor, window: targetWindow!)

        if inHotzone, !insideNotchHotzone {
            insideNotchHotzone = true
            if let window = targetWindow {
                surfaceShelf(on: window.viewModel)
            }
        } else if !inHotzone, insideNotchHotzone {
            insideNotchHotzone = false
        }
    }

    private func hasShelfCompatibleContent() -> Bool {
        let accepted: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.url.identifier),
            .string,
        ]
        guard let types = dragPasteboard.types else { return false }
        return types.contains(where: accepted.contains)
    }

    private func isInsideNotchHotzone(_ point: CGPoint, window: NotchWindow) -> Bool {
        let screen = window.attachedScreen
        let viewModel = window.viewModel
        let geometry = viewModel.notchGeometry
        let minWidth = geometry.notchWidth + (NotchViewModel.minWingWidth * 2)
        let panelWidth = max(geometry.notchWidth + (viewModel.wingWidth * 2), minWidth)
        let topY = screen.frame.maxY
        let leadIn: CGFloat = 40
        let hotzone = CGRect(
            x: screen.frame.midX - panelWidth / 2,
            y: topY - geometry.notchHeight - leadIn,
            width: panelWidth,
            height: geometry.notchHeight + leadIn
        )
        return hotzone.contains(point)
    }

    private func surfaceShelf(on model: NotchViewModel) {
        if WidgetRegistry.shared.widget(for: "file-shelf") != nil {
            model.currentExpandedWidgetID = "file-shelf"
        }
        model.forceExpand()
    }
}
