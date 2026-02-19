import SwiftUI
import Combine
import QuickLookThumbnailing
import UniformTypeIdentifiers

@Observable
@MainActor
final class FileShelfViewModel {
    // MARK: - Types

    struct ShelfItem: Identifiable {
        let id: UUID
        let url: URL
        let name: String
        let fileSize: Int64
        let icon: NSImage
        var thumbnail: NSImage?
        let addedAt: Date
        let fileType: UTType?
    }

    // MARK: - State
    var items: [ShelfItem] = []
    var isDragTargetActive: Bool = false

    var isAtCapacity: Bool {
        items.count >= SettingsManager.shared.fileShelfMaxItems
    }

    var itemCount: Int { items.count }
    var maxItems: Int { SettingsManager.shared.fileShelfMaxItems }

    // MARK: - Private
    private var expirationTimer: Timer?

    init() {}

    // MARK: - Public API

    func startMonitoring() {
        startExpirationTimer()
        loadPersistedItems()
    }

    func stopMonitoring() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        persistItems()
    }

    func addFile(_ url: URL) {
        guard !isAtCapacity else { return }
        guard !items.contains(where: { $0.url == url }) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let fileType = UTType(filenameExtension: url.pathExtension)

        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            fileSize = attrs[.size] as? Int64 ?? 0
        }

        let item = ShelfItem(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            fileSize: fileSize,
            icon: icon,
            thumbnail: nil,
            addedAt: Date(),
            fileType: fileType
        )

        items.append(item)
        EventBus.shared.send(.fileDropped(url))
        persistItems()

        // Generate thumbnail asynchronously
        generateThumbnail(for: url, itemId: item.id)
    }

    func removeFile(at id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            let url = items[index].url
            items.remove(at: index)
            EventBus.shared.send(.fileRemoved(id))
            persistItems()
        }
    }

    func removeFile(at offsets: IndexSet) {
        for index in offsets {
            if items.indices.contains(index) {
                EventBus.shared.send(.fileRemoved(items[index].id))
            }
        }
        items.remove(atOffsets: offsets)
        persistItems()
    }

    func clearAll() {
        items.removeAll()
        persistItems()
    }

    func openFile(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
    }

    // MARK: - Thumbnail Generation

    private func generateThumbnail(for url: URL, itemId: UUID) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 64, height: 64),
            scale: 2.0,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateRepresentations(for: request) { [weak self] thumbnail, _, error in
            guard let thumbnail else { return }
            Task { @MainActor in
                if let index = self?.items.firstIndex(where: { $0.id == itemId }) {
                    self?.items[index].thumbnail = thumbnail.nsImage
                }
            }
        }
    }

    // MARK: - Expiration

    private func startExpirationTimer() {
        expirationTimer = Timer.scheduledTimer(
            withTimeInterval: AnimationTokens.expirationCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.removeExpiredItems()
            }
        }
    }

    private func removeExpiredItems() {
        let hours = SettingsManager.shared.fileShelfExpirationHours
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let expired = items.filter { $0.addedAt < cutoff }

        for item in expired {
            EventBus.shared.send(.fileRemoved(item.id))
        }

        items.removeAll { $0.addedAt < cutoff }
        if !expired.isEmpty {
            persistItems()
        }
    }

    // MARK: - Persistence

    private let persistenceKey = "fileShelfItems"

    private func persistItems() {
        let urls = items.map { $0.url.absoluteString }
        let dates = items.map { $0.addedAt.timeIntervalSince1970 }
        UserDefaults.standard.set(urls, forKey: "\(persistenceKey)_urls")
        UserDefaults.standard.set(dates, forKey: "\(persistenceKey)_dates")
    }

    private func loadPersistedItems() {
        guard let urls = UserDefaults.standard.stringArray(forKey: "\(persistenceKey)_urls"),
              let dates = UserDefaults.standard.array(forKey: "\(persistenceKey)_dates") as? [TimeInterval]
        else { return }

        for (urlString, timestamp) in zip(urls, dates) {
            guard let url = URL(string: urlString),
                  FileManager.default.fileExists(atPath: url.path)
            else { continue }

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let fileType = UTType(filenameExtension: url.pathExtension)
            var fileSize: Int64 = 0
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                fileSize = attrs[.size] as? Int64 ?? 0
            }

            let item = ShelfItem(
                id: UUID(),
                url: url,
                name: url.lastPathComponent,
                fileSize: fileSize,
                icon: icon,
                thumbnail: nil,
                addedAt: Date(timeIntervalSince1970: timestamp),
                fileType: fileType
            )
            items.append(item)
            generateThumbnail(for: url, itemId: item.id)
        }

        // Remove any that have expired
        removeExpiredItems()
    }

    // MARK: - Helpers

    func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
