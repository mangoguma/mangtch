import Foundation
import QuartzCore

/// Manages a CVDisplayLink to synchronize callbacks with the display refresh rate.
///
/// Subscribers receive callbacks on the main thread at ~60fps (or the display's native
/// refresh rate). The display link starts automatically when the first subscriber registers
/// and stops when the last subscriber unsubscribes, keeping CPU usage at zero when idle.
///
/// Usage:
/// ```swift
/// let id = DisplayLinkManager.shared.subscribe { deltaTime in
///     // Called on main thread at display refresh rate
///     updateAnimation(deltaTime)
/// }
/// // Later:
/// DisplayLinkManager.shared.unsubscribe(id)
/// ```
final class DisplayLinkManager: @unchecked Sendable {
    static let shared = DisplayLinkManager()

    // MARK: - Types

    /// Callback receives the time delta (in seconds) since the last frame.
    typealias FrameCallback = (TimeInterval) -> Void

    // MARK: - State

    private var displayLink: CVDisplayLink?
    private var subscribers: [UUID: FrameCallback] = [:]
    private let lock = NSLock()
    private var lastTimestamp: UInt64 = 0

    // MARK: - Init

    private init() {}

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Register a callback to be invoked on the main thread each display refresh.
    /// Returns a UUID token used to unsubscribe.
    @discardableResult
    func subscribe(_ callback: @escaping FrameCallback) -> UUID {
        let id = UUID()
        lock.lock()
        subscribers[id] = callback
        let shouldStart = displayLink == nil
        lock.unlock()

        if shouldStart {
            start()
        }
        return id
    }

    /// Remove a subscriber. Stops the display link if no subscribers remain.
    func unsubscribe(_ id: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: id)
        let shouldStop = subscribers.isEmpty
        lock.unlock()

        if shouldStop {
            stop()
        }
    }

    // MARK: - Display Link Lifecycle

    private func start() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        lastTimestamp = 0

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (
            _ displayLink: CVDisplayLink,
            _ inNow: UnsafePointer<CVTimeStamp>,
            _ inOutputTime: UnsafePointer<CVTimeStamp>,
            _ flagsIn: CVOptionFlags,
            _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
            _ context: UnsafeMutableRawPointer?
        ) -> CVReturn in
            guard let context else { return kCVReturnSuccess }
            let manager = Unmanaged<DisplayLinkManager>.fromOpaque(context).takeUnretainedValue()
            manager.displayLinkFired(timestamp: inNow.pointee)
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stop() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
        lastTimestamp = 0
    }

    // MARK: - Frame Dispatch

    private func displayLinkFired(timestamp: CVTimeStamp) {
        // Calculate delta time from CVTimeStamp's hostTime (mach_absolute_time units)
        let currentHostTime = timestamp.hostTime
        let deltaTime: TimeInterval
        if lastTimestamp == 0 {
            // First frame -- use nominal refresh rate
            let period = CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink!)
            deltaTime = period > 0 ? period : (1.0 / 60.0)
        } else {
            // Convert mach_absolute_time delta to seconds
            var timebaseInfo = mach_timebase_info_data_t()
            mach_timebase_info(&timebaseInfo)
            let elapsedMach = currentHostTime - lastTimestamp
            let elapsedNanos = elapsedMach * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
            deltaTime = TimeInterval(elapsedNanos) / 1_000_000_000.0
        }
        lastTimestamp = currentHostTime

        // Snapshot subscribers under lock
        lock.lock()
        let callbacks = Array(subscribers.values)
        lock.unlock()

        // Dispatch to main thread
        DispatchQueue.main.async {
            for callback in callbacks {
                callback(deltaTime)
            }
        }
    }
}
