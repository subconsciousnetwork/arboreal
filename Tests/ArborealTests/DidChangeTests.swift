//
//  DidChangeTests.swift
//  
//
//  Created by Gordon Brander on 3/12/24.
//

import XCTest
import Observation
import Combine
@testable import Arboreal

final class DidChangeTests: XCTestCase {
    actor TestEnvironment {}

    enum TestAction: Hashable {
        case inc
    }

    @Observable
    final class TestModel: ModelProtocol {
        typealias Action = TestAction
        typealias Environment = TestEnvironment

        private(set) var count = 0

        func update(
            action: TestAction,
            environment: TestEnvironment
        ) -> Fx<TestAction> {
            switch action {
            case .inc:
                self.count = self.count + 1
                return Fx.none
            }
        }
    }

    var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        self.cancellables.removeAll()
    }

    @MainActor
    func testDidChangePublisher() throws {
        let store = Store(
            state: DidChangeDecorator(TestModel()),
            environment: TestEnvironment()
        )

        var count = 0
        var actions = Set<TestAction>()

        let cancellable = store.state.didChange.sink(receiveValue: { action in
            count = store.state.state.count
            actions.insert(action)
        })

        cancellables.insert(cancellable)

        XCTAssert(store.state.state.count == 0)

        store.send(.inc)

        XCTAssert(store.state.state.count == 1)
        XCTAssert(count == 1, "It published after the value changed")
        XCTAssert(actions.contains(.inc), "It published during the send")
        XCTAssert(actions.count == 1, "It published during the send")
    }

    @MainActor
    func testDidChangePublisherStoreExtension() throws {
        let store = Store(
            state: DidChangeDecorator(TestModel()),
            environment: TestEnvironment()
        )

        var count = 0
        var actions = Set<TestAction>()

        let cancellable = store.didChange.sink(receiveValue: { action in
            count = store.state.state.count
            actions.insert(action)
        })

        cancellables.insert(cancellable)

        XCTAssert(store.state.count == 0)

        store.send(.inc)

        XCTAssert(store.state.state.count == 1)
        XCTAssert(count == 1, "It published after the value changed")
        XCTAssert(actions.contains(.inc), "It published during the send")
        XCTAssert(actions.count == 1, "It published during the send")
    }

    @MainActor
    func testDynamicPropertyAccess() throws {
        let store = Store(
            state: DidChangeDecorator(TestModel()),
            environment: TestEnvironment()
        )

        XCTAssert(store.state.count == 0, "It can access the properties of the wrapped model")
    }

    @MainActor
    func testDeepObservationThroughDynamicPropertyAccess() throws {
        let store = Store(
            state: DidChangeDecorator(TestModel()),
            environment: TestEnvironment()
        )

        let expectation = XCTestExpectation(description: "didChange fired")

        withObservationTracking(
            {
                _ = store.state.count
            },
            onChange: {
                expectation.fulfill()
            }
        )

        store.send(.inc)

        wait(for: [expectation], timeout: 10.0)
    }
}
