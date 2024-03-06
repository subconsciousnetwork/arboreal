//
//  UpdateActionsTests.swift
//  
//
//  Created by Gordon Brander on 3/6/24.
//

import XCTest

import XCTest
import Arboreal
import SwiftUI
import Combine

@MainActor
class UpdateActionsTests: XCTestCase {
    enum TestAction: Hashable {
        case increment
        case setText(String)
        case delayedText(text: String, delay: Double)
        case delayedIncrement(delay: Double)
        case combo
    }

    @Observable
    class TestModel: ModelProtocol {
        typealias Action = TestAction
        typealias Environment = Void

        private(set) var count = 0
        private(set) var text = ""

        func update(
            action: TestAction,
            environment: Void
        ) -> Fx<TestAction> {
            switch action {
            case .increment:
                withAnimation {
                    self.count = self.count + 1
                }
                return Fx.none
            case .setText(let text):
                self.text = text
                return Fx.none
            case let .delayedText(text, delay):
                return Fx {
                    try? await Task.sleep(for: .seconds(delay))
                    return .setText(text)
                }
            case let .delayedIncrement(delay):
                return Fx {
                    try? await Task.sleep(for: .seconds(delay))
                    return .increment
                }
            case .combo:
                return update(
                    actions: [
                        .increment,
                        .increment,
                        .delayedIncrement(delay: 0.02),
                        .delayedText(text: "Test", delay: 0.01),
                        .increment
                    ],
                    environment: environment
                )
            }
        }
    }

    func testUpdateActions() throws {
        let store = Store(
            state: TestModel(),
            environment: ()
        )
        store.send(.combo)
        let expectation = XCTestExpectation(
            description: "Autofocus sets editor focus"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(
                store.state.count,
                4,
                "All increments run. Fx merged."
            )
            XCTAssertEqual(
                store.state.text,
                "Test",
                "Text set"
            )
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.2)
    }
}
