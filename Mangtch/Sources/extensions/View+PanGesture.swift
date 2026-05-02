import AppKit
import SwiftUI

enum PanAxis {
    case down, up, left, right

    var isHorizontal: Bool {
        self == .left || self == .right
    }
}

extension View {
    /// Detects a directional trackpad pan over this view via NSEvent's
    /// scroll-wheel monitor. The callback fires once when accumulated
    /// movement crosses `threshold`, again on each subsequent change,
    /// and finally with `.ended` when the gesture stops or reverses.
    func panGesture(
        axis: PanAxis,
        threshold: CGFloat = 30,
        _ handler: @escaping (CGFloat, PanPhase) -> Void
    ) -> some View {
        background(
            ScrollPanReader(axis: axis, threshold: threshold, handler: handler)
        )
    }
}

enum PanPhase {
    case began, changed, ended
}

private struct ScrollPanReader: NSViewRepresentable {
    let axis: PanAxis
    let threshold: CGFloat
    let handler: (CGFloat, PanPhase) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.refresh(axis: axis, threshold: threshold, handler: handler)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(axis: axis, threshold: threshold, handler: handler)
    }

    @MainActor
    final class Coordinator: NSObject {
        private var axis: PanAxis
        private var threshold: CGFloat
        private var handler: (CGFloat, PanPhase) -> Void

        private weak var hostView: NSView?
        private var monitor: Any?
        private var sum: CGFloat = 0
        private var fired = false
        private var idleTimer: Task<Void, Never>?

        init(axis: PanAxis, threshold: CGFloat, handler: @escaping (CGFloat, PanPhase) -> Void) {
            self.axis = axis
            self.threshold = threshold
            self.handler = handler
        }

        func refresh(axis: PanAxis, threshold: CGFloat, handler: @escaping (CGFloat, PanPhase) -> Void) {
            self.axis = axis
            self.threshold = threshold
            self.handler = handler
        }

        func attach(to view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                if event.window === self.hostView?.window {
                    self.consume(event)
                }
                return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            idleTimer?.cancel()
            idleTimer = nil
            sum = 0
            fired = false
        }

        private func consume(_ event: NSEvent) {
            if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                endPan()
                return
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            // Reject events that aren't dominantly along the configured axis.
            let primary = axis.isHorizontal ? abs(dx) : abs(dy)
            let secondary = axis.isHorizontal ? abs(dy) : abs(dx)
            guard primary >= secondary * 1.4 else { return }

            // macOS scroll-delta convention: positive deltaY = scrolling
            // content down (revealing items below); positive deltaX = right.
            // Match that so .down fires on a "pull down" trackpad scroll.
            let signedDelta: CGFloat
            switch axis {
            case .down:  signedDelta =  dy
            case .up:    signedDelta = -dy
            case .right: signedDelta =  dx
            case .left:  signedDelta = -dx
            }

            // Mouse wheels report integer ticks; trackpads report fine deltas.
            // Scale wheel ticks up so a single click can clear the threshold.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 6
            let step = signedDelta * scale

            // Reverse direction → reset accumulator (gesture is no longer
            // continuous in the desired direction).
            if step < -0.2 {
                if fired { handler(sum, .ended) }
                sum = 0
                fired = false
                return
            }

            guard step > 0.2 else { return }
            sum += step

            if !fired && sum >= threshold {
                fired = true
                handler(sum, .began)
            } else if fired {
                handler(sum, .changed)
            }

            scheduleIdleEnd()
        }

        private func scheduleIdleEnd() {
            idleTimer?.cancel()
            idleTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard let self, !Task.isCancelled else { return }
                self.endPan()
            }
        }

        private func endPan() {
            idleTimer?.cancel()
            idleTimer = nil
            if fired {
                handler(sum, .ended)
            }
            sum = 0
            fired = false
        }
    }
}
