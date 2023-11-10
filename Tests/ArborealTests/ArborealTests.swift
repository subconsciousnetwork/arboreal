import XCTest
import Observation
@testable import Arboreal

final class ArborealTests: XCTestCase {
    enum Action: Hashable {
        case setText(String)
    }

    @Observable
    class Model: ModelProtocol {
        private(set) var text = ""
        private(set) var edits: Int = 0
        
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
    
    /// Test creating binding for an address
    func testSend() async throws {
        let store = Store(
            state: Model(),
            environment: ()
        )
        
        store.send(.setText("Foo"))
        
        XCTAssertEqual(
            store.state.text,
            "Foo"
        )
        XCTAssertEqual(
            store.state.edits,
            1
        )
    }
}
