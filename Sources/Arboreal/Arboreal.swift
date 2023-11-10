//
//  Arboreal.swift
//  ObservablePlayground
//
//  Created by Gordon Brander on 11/7/23.
//

import SwiftUI
import Observation
import os

/// State is described with models.
/// A model is any type that knows how to update itself in response to actions.
/// Models can be value or reference types. It's typical to create
/// `@Observable` models.
public protocol ModelProtocol {
    associatedtype Action
    associatedtype Environment

    /// Update model in response to action, returning any side-effects (Fx).
    /// Update also receives an environment, which contains services it can
    /// use to produce side-effects.
    mutating func update(
        action: Action,
        environment: Environment
    ) -> Fx<Action>
}

/// A mailbox is any type that implements a send method which can receive
/// actions. Stores are mailboxes.
public protocol MailboxProtocol {
    associatedtype Action

    func send(_ action: Action)
}

/// Stores hold state and can receive actions via `send`.
public protocol StoreProtocol: MailboxProtocol {
    associatedtype Model: ModelProtocol where Model.Action == Action

    /// State should be get-only for stores.
    var state: Model { get }
}

/// Fx represents a collection of side-effects... things like http requests
/// or database calls that reference or mutate some outside resource.
///
/// Effects are modeled as async closures, which return an action representing
/// the result of the effect, for example, an HTTP response. Actions are
/// expected to model both success and failure cases.
///
/// Usage:
///
///     Fx {
///         let rows = environment.database.getPosts()
///         return rows.first
///     }
public struct Fx<Action> {
    /// No effects. Return this when your update function produces
    /// no side-effects.
    ///
    /// Usage:
    ///
    ///     func update(
    ///         action: Action,
    ///         environment: Environment
    ///     ) -> Fx<Action> {
    ///         return Fx.none
    ///     }
    public static var none: Self {
        Self()
    }
    
    /// An effect is an async thunk (zero-arg closure) that returns an Action.
    public typealias Effect = () async -> Action

    /// The batch of side-effects represented by this fx instance.
    public var effects: [Effect] = []
    
    /// Create an `Fx` with a single effect.
    public init(_ effect: @escaping Effect) {
        self.effects = [effect]
    }
    
    /// Create an `Fx` with an array of effects.
    public init(_ effects: [Effect] = []) {
        self.effects = effects
    }
    
    /// Merge two fx instances together.
    /// - Returns a new Fx containing the combined effects.
    public func merge(_ otherFx: Self) -> Self {
        var merged = self.effects
        merged.append(contentsOf: otherFx.effects)
        return Fx(merged)
    }

    /// Map effects, transforming their actions with `tag`.
    /// Used to map child component updates to parent context.
    ///
    /// Usage:
    ///
    ///     child
    ///         .update(action: action, environment: environment)
    ///         .map(tagChild)
    ///
    /// - Returns a new Fx containing the tagged effects.
    public func map<TaggedAction>(
        _ tag: @escaping (Action) -> TaggedAction
    ) -> Fx<TaggedAction> {
        Fx<TaggedAction>(
            effects.map({ effect in
                { await tag(effect()) }
            })
        )
    }
}

/// EffectRunner is an actor that runs all effects for a given store.
/// Effects are isolated to this actor, keeping them off the main thread, and
/// local to this effect runner.
actor EffectRunner<Mailbox: MailboxProtocol & AnyObject> {
    /// Mailbox to notify when effect completes.
    /// We keep a weak reference to the mailbox, since it is expected
    /// to hold a reference to this EffectRunner.
    private weak var mailbox: Mailbox?
    
    /// Create a new effect runner.
    /// - Parameters:
    ///   - mailbox: the mailbox to send actions tos
    public init(_ mailbox: Mailbox) {
        self.mailbox = mailbox
    }
    
    /// Run a batch of effects in parallel.
    /// Actions are sent to mailbox in whatever order the tasks complete.
    public nonisolated func run(
        _ fx: Fx<Mailbox.Action>
    ) {
        for effect in fx.effects {
            Task {
                let action = await effect()
                await self.mailbox?.send(action)
            }
        }
    }
}

/// Store is a source of truth for application state.
///
/// Store hold a get-only `state` which conforms to `ModelProtocol` and knows
/// how to update itself and generate side-effects. All updates and effects
/// to this state happen through actions sent to `store.send`.
///
/// Store is `@Observable`, and can hold a state that is either a value-type
/// model, or a reference-type models that are also `@Observable`.
///
/// When using a hierarchy of observable `ModelProtocols` with Store,
/// it is strongly recommended that you mark all properties of your
/// models with `private(set)`, so that all updates are forced to go through
/// `Model.update(action:environment:)`. This ensures there is only one code
/// path that can modify state, making code more easily testable and reliable.
@Observable public final class Store<Model: ModelProtocol>: StoreProtocol {
    /// Logger for store. You can customize this in the initializer.
    var logger: Logger
    /// Runs all effects returned by model update functions.
    @ObservationIgnored private lazy var runner = EffectRunner(self)
    /// An environment for the model update function
    @ObservationIgnored public var environment: Model.Environment

    /// A read-only view of the current state.
    /// Nested models and other reference types should also mark their
    /// properties read-only. All state updates should go through
    /// `Model.update()`.
    public private(set) var state: Model
    
    /// Create a Store
    /// - Parameters:
    ///   - state: the initial state for the store. Must conform to
    ///     `ModelProtocol`.
    ///   - `environment`: an environment with services that can be used by the
    ///     model to create side-effects.
    public init(
        state: Model,
        environment: Model.Environment,
        logger: Logger = Logger(
            subsystem: "ObservableStore",
            category: "Store"
        )
    ) {
        self.state = state
        self.environment = environment
        self.logger = logger
    }
    
    /// Send an action to store, updating state, and running effects.
    /// Calls the update method of the underlying model to update state and
    /// generate effects. Effects are run and the resulting actions are sent
    /// back into store, in whatever order the effects complete.
    public func send(_ action: Model.Action) -> Void {
        let actionDescription = String(describing: action)
        logger.debug("Action: \(actionDescription)")
        let fx = state.update(
            action: action,
            environment: environment
        )
        runner.run(fx)
    }
}

/// Create a ViewStore, a scoped view over a store.
/// ViewStore is conceptually like a SwiftUI Binding. However, instead of
/// offering get/set for some source-of-truth, it offers a StoreProtocol.
///
/// Using ViewStore, you can create self-contained views that work with their
/// own domain
public struct ViewStore<Model: ModelProtocol>: StoreProtocol {
    /// `_get` reads some source of truth dynamically, using a closure.
    ///
    /// NOTE: We've found this to be important for some corner cases in
    /// SwiftUI components, where capturing the state by value may produce
    /// unexpected issues. Examples are input fields and NavigationStack,
    /// which both expect a Binding to a state (which dynamically reads
    /// the value using a closure). Using the same approach as Binding
    /// offers the most reliable results.
    private var _get: () -> Model
    private var _send: (Model.Action) -> Void

    /// Initialize a ViewStore from a `get` closure and a `send` closure.
    /// These closures read from a parent store to provide a type-erased
    /// view over the store that only exposes domain-specific
    /// model and actions.
    public init(
        get: @escaping () -> Model,
        send: @escaping (Model.Action) -> Void
    ) {
        self._get = get
        self._send = send
    }

    /// Get the current state from the underlying model.
    public var state: Model {
        self._get()
    }

    /// Send an action to the underlying store through ViewStore.
    public func send(_ action: Model.Action) {
        self._send(action)
    }
}

extension StoreProtocol {
    /// Create a viewStore from a StoreProtocol
    public func viewStore<ChildModel: ModelProtocol>(
        get: @escaping (Model) -> ChildModel,
        tag: @escaping (ChildModel.Action) -> Action
    ) -> ViewStore<ChildModel> {
        ViewStore(
            get: { get(self.state) },
            send: { action in self.send(tag(action)) }
        )
    }
}

extension Binding {
    /// Create a `Binding` from a `StoreProtocol`.
    /// - Parameters:
    ///   - `store` is a reference to the store
    ///   - `get` reads the value from the state.
    ///   - `tag` tags the value, turning it into an action for `send`
    /// - Returns a binding suitable for use in a vanilla SwiftUI view.
    public init<Store: StoreProtocol>(
        store: Store,
        get: @escaping (Store.Model) -> Value,
        tag: @escaping (Value) -> Store.Model.Action
    ) {
        self.init(
            get: { get(store.state) },
            set: { value in
                store.send(tag(value))
            }
        )
    }
}

extension StoreProtocol {
    /// Initialize a `Binding` from a `StoreProtocol`.
    /// - Parameters:
    ///   - `get` reads the value from the state.
    ///   - `tag` tags the value, turning it into an action for `send`
    /// - Returns a binding suitable for use in a vanilla SwiftUI view.
    public func binding<Value>(
        get: @escaping (Model) -> Value,
        tag: @escaping (Value) -> Action
    ) -> Binding<Value> {
        Binding(store: self, get: get, tag: tag)
    }
}
