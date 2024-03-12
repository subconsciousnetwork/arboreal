//
//  BindingTests.swift
//
//
//  Created by Gordon Brander on 9/21/22.
//

import XCTest
import SwiftUI
import Observation
@testable import Arboreal

final class BindingTests: XCTestCase {
    enum Action: Hashable {
        case setText(String)
    }
    
    @Observable
    class Model: ArborealModel {
        private(set) var text = ""
        private(set) var edits: Int = 0
        
        @MainActor
        func update(
            action: Action,
            environment: Void
        ) -> Fx<Action> {
            switch action {
            case .setText(let text):
                self.text = text
                self.edits = self.edits + 1
                return Fx.none
            }
        }
    }
    
    struct SimpleView: View {
        @Binding var text: String
        
        var body: some View {
            Text(text)
        }
    }
    
    /// Test creating binding for an address
    @MainActor
    func testBinding() throws {
        let store = Store(
            state: Model(),
            environment: ()
        )
        
        let binding = Binding(
            store: store,
            get: \.text,
            tag: Action.setText
        )
        
        let view = SimpleView(text: binding)
        
        view.text = "Foo"
        view.text = "Bar"

        XCTAssertEqual(
            store.state.text,
            "Bar"
        )
        XCTAssertEqual(
            store.state.edits,
            2
        )
    }
    
    /// Test creating binding for an address
    @MainActor
    func testBindingMethod() throws {
        let store = Store(
            state: Model(),
            environment: ()
        )

        let binding = store.binding(
            get: \.text,
            tag: Action.setText
        )

        let view = SimpleView(text: binding)

        view.text = "Foo"
        view.text = "Bar"

        XCTAssertEqual(
            store.state.text,
            "Bar"
        )
        XCTAssertEqual(
            store.state.edits,
            2
        )
    }
}
