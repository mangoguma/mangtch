import SwiftUI
import Combine

struct DownloadInfo: Identifiable {
    let id = UUID()
    let fileName: String
    var currentSize: Int64
    var estimatedTotalSize: Int64?
    var isComplete: Bool = false
    var startTime: Date = Date()

    var progress: Double {
        guard let total = estimatedTotalSize, total > 0 else { return 0 }
        return min(1.0, Double(currentSize) / Double(total))
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: currentSize, countStyle: .file)
    }

    var formattedTotal: String? {
        guard let total = estimatedTotalSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var speed: String {
        let elapsed = elapsedTime
        guard elapsed > 0 else { return "" }
        let bytesPerSec = Int64(Double(currentSize) / elapsed)
        return ByteCountFormatter.string(fromByteCount: bytesPerSec, countStyle: .file) + "/s"
    }
}

@Observable
@MainActor
final class DownloadViewModel {
    // MARK: - State

    private(set) var activeDownloads: [DownloadInfo] = []
    private(set) var isMonitoring = false

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var totalProgress: Double {
        guard !activeDownloads.isEmpty else { return 0 }
        let totalProgress = activeDownloads.reduce(0.0) { $0 + $1.progress }
        return totalProgress / Double(activeDownloads.count)
    }

    var activeCount: Int {
        activeDownloads.filter { !$0.isComplete }.count
    }

    // MARK: - Private

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var trackedFiles: [String: DownloadInfo] = [:]

    private let downloadsURL: URL = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }()

    /// File extensions indicating an in-progress download
    private let downloadExtensions = Set(["crdownload", "download", "part", "tmp"])

    // MARK: - Lifecycle

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        // Initial scan
        scanForDownloads()

        // Poll every 1 second to update file sizes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForDownloads()
            }
        }

        // Set up FSEvents via DispatchSource for immediate notification
        let fd = open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scanForDownloads()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        dispatchSource = source
    }

    func stopMonitoring() {
        isMonitoring = false
        pollTimer?.invalidate()
        pollTimer = nil
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Scanning

    private func scanForDownloads() {
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var currentFiles = Set<String>()

        for url in contents {
            let ext = url.pathExtension.lowercased()
            guard downloadExtensions.contains(ext) else { continue }

            let name = url.lastPathComponent
            currentFiles.insert(name)

            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0

            if var existing = trackedFiles[name] {
                // Update existing download
                existing.currentSize = Int64(fileSize)
                trackedFiles[name] = existing
            } else {
                // New download detected
                var info = DownloadInfo(
                    fileName: name,
                    currentSize: Int64(fileSize)
                )
                // Estimate total from file size growth over time
                trackedFiles[name] = info
            }
        }

        // Mark completed (disappeared temp files = download finished)
        for key in trackedFiles.keys {
            if !currentFiles.contains(key) {
                trackedFiles[key]?.isComplete = true
            }
        }

        // Remove completed downloads after 3 seconds
        let completedKeys = trackedFiles.filter { $0.value.isComplete }.map { $0.key }
        if !completedKeys.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                for key in completedKeys {
                    self.trackedFiles.removeValue(forKey: key)
                }
                self.updateActiveList()
            }
        }

        updateActiveList()
    }

    private func updateActiveList() {
        activeDownloads = trackedFiles.values
            .sorted { $0.startTime < $1.startTime }
    }
}
