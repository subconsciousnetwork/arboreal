//
//  DidUpdate.swift
//  Provides a decorator class for models that exposes a `didUpdate` publisher.
//
//  Created by Gordon Brander on 3/12/24.
//

import Foundation
import Combine

public protocol ArborealDidUpdateProtocol {
    associatedtype Action

    var didUpdate: AnyPublisher<Action, Never> { get }
}

/// Wrap a model, exposing a `didUpdate` publisher that publishes an action
/// immediately *after* the state of the model has changed
@Observable
@dynamicMemberLookup
public final class DidUpdateDecorator<Model: ArborealModel>:
    ArborealModel,
    ArborealDidUpdateProtocol
{
    public typealias Action = Model.Action
    public typealias Environment = Model.Environment

    @MainActor
    public private(set) var state: Model

    @ObservationIgnored
    private var _didUpdate = PassthroughSubject<Action, Never>()

    /// Publishes the action that changed the model state, *immediately after*
    /// the state has changed.
    public var didUpdate: AnyPublisher<Action, Never> {
        _didUpdate.eraseToAnyPublisher()
    }

    @MainActor
    public init(_ state: Model) {
        self.state = state
    }

    @MainActor
    public subscript<T>(dynamicMember keyPath: KeyPath<Model, T>) -> T {
        state[keyPath: keyPath]
    }

    @MainActor
    public func update(
        action: Action,
        environment: Environment
    ) -> Fx<Action> {
        let fx = state.update(action: action, environment: environment)
        _didUpdate.send(action)
        return fx
    }
}

extension DidUpdateDecorator: Equatable where Model: Equatable {
    @MainActor
    public static func == (
        lhs: DidUpdateDecorator<Model>,
        rhs: DidUpdateDecorator<Model>
    ) -> Bool {
        lhs.state == rhs.state
    }
}

public extension ArborealStore where Model: ArborealDidUpdateProtocol {
    @MainActor
    var didUpdate: AnyPublisher<Model.Action, Never> {
        self.state.didUpdate.eraseToAnyPublisher()
    }
}
