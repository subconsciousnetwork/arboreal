//
//  ViewStoreTests.swift
//  
//
//  Created by Gordon Brander on 3/6/24.
//

import XCTest
import SwiftUI
@testable import Arboreal

final class ViewStoreTests: XCTestCase {
    enum ParentAction: Hashable {
        case child(ChildAction)
        case setText(String)

        static func tag(_ action: ChildAction) -> ParentAction {
            switch action {
            case .setText(let string):
                return .setText(string)
            }
        }
    }

    @Observable
    class ParentModel: ModelProtocol {
        private(set) var child = ChildModel(text: "")
        private(set) var edits: Int = 0

        func update(
            action: ParentAction,
            environment: Void
        ) -> Fx<ParentAction> {
            switch action {
            case .child(let action):
                return self.child.update(
                    action: action,
                    environment: ()
                )
                .tag(ParentAction.child)
            case .setText(let text):
                self.edits = self.edits + 1
                return child.update(
                    action: .setText(text),
                    environment: ()
                )
                .tag(ParentAction.child)
            }
        }
    }

    enum ChildAction: Hashable {
        case setText(String)
    }

    @Observable
    class ChildModel: ModelProtocol {
        private(set) var text: String

        init(text: String = "") {
            self.text = text
        }

        func update(
            action: ChildAction,
            environment: Void
        ) -> Fx<ChildAction> {
            switch action {
            case .setText(let string):
                withAnimation {
                    self.text = string
                }
                return Fx.none
            }
        }
    }

    /// Test creating binding for an address
    func testViewStore() async throws {
        let store = Store(
            state: ParentModel(),
            environment: ()
        )

        let viewStore = store.viewStore(
            get: \.child,
            tag: ParentAction.tag
        )

        await viewStore.transact(.setText("Foo"))

        XCTAssertEqual(
            store.state.child.text,
            "Foo"
        )
        XCTAssertEqual(
            store.state.edits,
            1
        )
    }
}
