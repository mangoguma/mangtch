import AppKit
import UniformTypeIdentifiers

/// Watches for a system-wide file drag and surfaces the FileShelf as soon
/// as the cursor enters the notch's hit zone — so the user gets a visible
/// drop target without having to first hover the notch into the open state.
///
/// macOS doesn't publish "a file drag is in progress" directly. We infer it
/// by snapshotting the drag pasteboard's changeCount on mouse-down: if it
/// has incremented by the time we see mouse-dragged events, AppKit started
/// a drag session in another app and put a payload on the drag board.
@MainActor
final class DragDetector {
    static let shared = DragDetector()

    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private let dragPasteboard = NSPasteboard(name: .drag)
    private var pasteboardSnapshot = 0
    private var sessionActive = false
    private var contentDragConfirmed = false
    private var insideNotchHotzone = false

    private init() {}

    func start() {
        stop()
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.beginSession() }
        }
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleDrag(event) }
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.endSession() }
        }
    }

    func stop() {
        for token in [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(token)
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        sessionActive = false
        contentDragConfirmed = false
        insideNotchHotzone = false
    }

    private func beginSession() {
        pasteboardSnapshot = dragPasteboard.changeCount
        sessionActive = true
        contentDragConfirmed = false
        insideNotchHotzone = false
    }

    private func endSession() {
        sessionActive = false
        contentDragConfirmed = false
        insideNotchHotzone = false
    }

    private func handleDrag(_ event: NSEvent) {
        guard sessionActive else { return }

        if !contentDragConfirmed {
            // Content lands on the drag pasteboard a moment after the user
            // starts moving — keep checking until the changeCount bumps.
            guard dragPasteboard.changeCount != pasteboardSnapshot else { return }
            guard hasShelfCompatibleContent() else {
                sessionActive = false
                return
            }
            contentDragConfirmed = true
        }

        let cursor = NSEvent.mouseLocation
        let inHotzone = isInsideNotchHotzone(cursor)

        if inHotzone, !insideNotchHotzone {
            insideNotchHotzone = true
            surfaceShelf()
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

    /// The hit zone is the notch's footprint plus a small lead-in below it
    /// so users approaching from the screen don't have to thread the needle.
    private func isInsideNotchHotzone(_ point: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return false
        }
        let geometry = NotchViewModel.shared.notchGeometry
        let panelWidth = geometry.notchWidth + (NotchViewModel.shared.wingWidth * 2)
        let topY = screen.frame.maxY
        let leadIn: CGFloat = 24
        let hotzone = CGRect(
            x: screen.frame.midX - panelWidth / 2,
            y: topY - geometry.notchHeight - leadIn,
            width: panelWidth,
            height: geometry.notchHeight + leadIn
        )
        return hotzone.contains(point)
    }

    private func surfaceShelf() {
        let model = NotchViewModel.shared
        if WidgetRegistry.shared.widget(for: "file-shelf") != nil {
            model.currentExpandedWidgetID = "file-shelf"
        }
        model.forceExpand()
    }
}
