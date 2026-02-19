import SwiftUI
import UniformTypeIdentifiers

struct FileShelfDropDelegate: DropDelegate {
    let viewModel: FileShelfViewModel

    func validateDrop(info: DropInfo) -> Bool {
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }
        return !viewModel.isAtCapacity
    }

    func dropEntered(info: DropInfo) {
        viewModel.isDragTargetActive = true

        // Expand panel to show file shelf
        Task { @MainActor in
            NotchViewModel.shared.expand()
        }
    }

    func dropExited(info: DropInfo) {
        viewModel.isDragTargetActive = false
    }

    func performDrop(info: DropInfo) -> Bool {
        viewModel.isDragTargetActive = false

        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }

                Task { @MainActor in
                    viewModel.addFile(url)
                }
            }
        }

        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if viewModel.isAtCapacity {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .copy)
    }
}
