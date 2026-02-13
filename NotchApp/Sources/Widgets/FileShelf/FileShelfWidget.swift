import SwiftUI

@MainActor
final class FileShelfWidget: NotchWidget {
    let id = "file-shelf"
    let displayName = "File Shelf"
    let icon = "tray"
    let preferredPosition: WidgetPosition = .leftWing
    var isEnabled: Bool = true

    private let viewModel = FileShelfViewModel()

    @MainActor
    func makeCompactView() -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                if viewModel.items.isEmpty {
                    // Empty state
                    Image(systemName: "tray")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    // Show up to 3 items
                    ForEach(viewModel.items.prefix(3)) { item in
                        FileShelfItemView(
                            item: item,
                            onRemove: { self.viewModel.removeFile(at: item.id) },
                            onOpen: { self.viewModel.openFile(item) },
                            onReveal: { self.viewModel.revealInFinder(item) }
                        )
                    }

                    if viewModel.items.count > 3 {
                        Text("+\(viewModel.items.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .onDrop(of: [.fileURL], delegate: FileShelfDropDelegate(viewModel: viewModel))
        )
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Label("File Shelf", systemImage: "tray")
                        .font(.headline)

                    Spacer()

                    Text("\(viewModel.itemCount)/\(viewModel.maxItems)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !viewModel.items.isEmpty {
                        Button("Clear All") {
                            self.viewModel.clearAll()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }

                if viewModel.items.isEmpty {
                    // Drop zone
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)

                        Text("Drop files here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                viewModel.isDragTargetActive ? Color.accentColor : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                            )
                    )
                } else {
                    // File grid
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 64), spacing: 12)
                    ], spacing: 12) {
                        ForEach(viewModel.items) { item in
                            FileShelfItemView(
                                item: item,
                                onRemove: { self.viewModel.removeFile(at: item.id) },
                                onOpen: { self.viewModel.openFile(item) },
                                onReveal: { self.viewModel.revealInFinder(item) }
                            )
                        }
                    }
                }
            }
            .padding()
            .onDrop(of: [.fileURL], delegate: FileShelfDropDelegate(viewModel: viewModel))
        )
    }

    func activate() {
        Task { @MainActor in
            viewModel.startMonitoring()
        }
    }

    func deactivate() {
        Task { @MainActor in
            viewModel.stopMonitoring()
        }
    }
}
