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

        // Surface the file shelf regardless of where the drop target sits
        // (wing icon, wings row, or already inside the panel) and regardless
        // of the panel's current state — the user is mid-drag and shouldn't
        // need to hover-then-drop in two motions.
        Task { @MainActor in
            for vm in NotchWindowManager.shared.allViewModels {
                vm.currentExpandedWidgetID = "file-shelf"
                vm.forceExpand()
            }
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
