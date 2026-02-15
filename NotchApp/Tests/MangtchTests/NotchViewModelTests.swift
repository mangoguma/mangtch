import XCTest
import Combine
@testable import Mangtch

@MainActor
final class NotchViewModelTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitialStateIsIdle() {
        let vm = NotchViewModel.shared
        // Reset state for testing
        vm.collapse()
        XCTAssertEqual(vm.currentState, .idle)
    }

    func testHoverTransition() async {
        let vm = NotchViewModel.shared
        vm.collapse() // ensure idle

        // Hover triggers debounced transition
        vm.hover()

        // Wait for debounce
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(vm.currentState, .hovering)
    }

    func testExpandFromHovering() async {
        let vm = NotchViewModel.shared
        vm.collapse()
        vm.hover()
        try? await Task.sleep(for: .milliseconds(100))

        vm.expand()
        XCTAssertEqual(vm.currentState, .expanded)
    }

    func testExpandFromIdleFails() {
        let vm = NotchViewModel.shared
        vm.collapse()

        vm.expand() // Should not work from idle
        XCTAssertEqual(vm.currentState, .idle)
    }

    func testCollapseFromExpanded() async {
        let vm = NotchViewModel.shared
        vm.collapse()
        vm.hover()
        try? await Task.sleep(for: .milliseconds(100))
        vm.expand()

        vm.collapse()
        XCTAssertEqual(vm.currentState, .idle)
    }

    func testCollapseFromHovering() async {
        let vm = NotchViewModel.shared
        vm.collapse()
        vm.hover()
        try? await Task.sleep(for: .milliseconds(100))

        vm.collapse()
        XCTAssertEqual(vm.currentState, .idle)
    }

    func testPanelWidthChangesWithState() async {
        let vm = NotchViewModel.shared
        vm.collapse()

        let idleWidth = vm.panelWidth

        vm.hover()
        try? await Task.sleep(for: .milliseconds(100))

        // Hovering should have wider panel
        XCTAssertGreaterThan(vm.panelWidth, idleWidth)
    }
}
