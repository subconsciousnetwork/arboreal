//
//  DidChange.swift
//  Provides a decorator class for models that exposes a `didChange` publisher.
//
//  Created by Gordon Brander on 3/12/24.
//

import Foundation
import Combine

public protocol DidChangeProtocol {
    associatedtype Action

    var didChange: AnyPublisher<Action, Never> { get }
}

/// Wrap a model, exposing a `willChange` publisher that publishes an event
/// immediately *after* the state of the model has changed
@Observable
@dynamicMemberLookup
public final class DidChangeDecorator<Model: ModelProtocol>:
    ModelProtocol,
    DidChangeProtocol
{
    public typealias Action = Model.Action
    public typealias Environment = Model.Environment

    @MainActor
    public private(set) var state: Model

    @ObservationIgnored
    private var _didChange = PassthroughSubject<Action, Never>()

    /// Publishes the action that changed the model state, *immediately after*
    /// the state has changed.
    public var didChange: AnyPublisher<Action, Never> {
        _didChange.eraseToAnyPublisher()
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
        _didChange.send(action)
        return fx
    }
}

extension DidChangeDecorator: Equatable where Model: Equatable {
    @MainActor
    public static func == (
        lhs: DidChangeDecorator<Model>,
        rhs: DidChangeDecorator<Model>
    ) -> Bool {
        lhs.state == rhs.state
    }
}

public extension StoreProtocol where Model: DidChangeProtocol {
    @MainActor
    var didChange: AnyPublisher<Model.Action, Never> {
        self.state.didChange.eraseToAnyPublisher()
    }
}
