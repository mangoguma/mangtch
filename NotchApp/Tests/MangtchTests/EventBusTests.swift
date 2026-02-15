import XCTest
import Combine
@testable import Mangtch

final class EventBusTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func testPublishAndSubscribe() {
        let expectation = expectation(description: "Event received")
        let bus = EventBus.shared

        bus.publisher
            .sink { event in
                if case .stateChanged(.hovering) = event {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        bus.send(.stateChanged(.hovering))

        waitForExpectations(timeout: 1)
    }

    func testStateChangesFilter() {
        let expectation = expectation(description: "State change received")
        let bus = EventBus.shared

        bus.stateChanges
            .sink { state in
                XCTAssertEqual(state, .expanded)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Send non-state event first (should be filtered)
        bus.send(.screenChanged)

        // Send state event (should pass through)
        bus.send(.stateChanged(.expanded))

        waitForExpectations(timeout: 1)
    }

    func testHUDTriggerFilter() {
        let expectation = expectation(description: "HUD trigger received")
        let bus = EventBus.shared

        bus.hudTriggers
            .sink { (type, value) in
                XCTAssertEqual(type, .volume)
                XCTAssertEqual(value, 0.75, accuracy: 0.01)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        bus.send(.hudTriggered(.volume, 0.75))

        waitForExpectations(timeout: 1)
    }

    func testMultipleSubscribers() {
        let expectation1 = expectation(description: "Subscriber 1")
        let expectation2 = expectation(description: "Subscriber 2")
        let bus = EventBus.shared

        bus.publisher
            .sink { _ in expectation1.fulfill() }
            .store(in: &cancellables)

        bus.publisher
            .sink { _ in expectation2.fulfill() }
            .store(in: &cancellables)

        bus.send(.screenChanged)

        waitForExpectations(timeout: 1)
    }
}
