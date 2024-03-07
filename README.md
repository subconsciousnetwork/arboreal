# Arboreal

A simple Elm-like Store for SwiftUI.

Arboreal helps you craft more reliable apps, by centralizing all of your application state into one place and giving you a deterministic system for managing state changes and side-effects. All state changes happen through actions passed to an update function. This guarantees your application will produce exactly the same state, given the same actions in the same order. If you’ve ever used [Elm](https://guide.elm-lang.org/architecture/) or [Redux](https://redux.js.org/), you get the gist.

Arboreal's `Store` based on the  [@Observable macro](https://developer.apple.com/documentation/observation) for fine-grained reactivity. This means you can centralize all of your application state while achieving the same fast performance you would get with localized view state. Store works just like any `@Observable`. State can passed down to sub-views as `@Binding` or as ordinary properties. You can also create scoped child stores with `ViewStore`, 

## Example

A minimal example of Store used to increment a count with a button.

```swift
import SwiftUI
import Combine
import Arboreal

/// Actions
enum AppAction {
    case increment
}

/// Services like API methods go here
actor AppEnvironment {
}

/// Conform your model to `ModelProtocol`.
/// A `ModelProtocol` is an `@Observable` with an update function like the
/// one below.
@Observable
class AppModel: ModelProtocol {
    /// Mark prop get-only so that model can only be updated via update method
    private(set) var count = 0

    /// Update method
    /// Modifies state and returns any side-effects
    func update(
        action: AppAction,
        environment: AppEnvironment
    ) -> Fx<AppAction> {
        switch action {
        case .increment:
            self.count = self.count + 1
            return Fx.none
        }
    }
}

struct AppView: View {
    @State private var store = Store(
        state: AppModel(),
        environment: AppEnvironment()
    )

    var body: some View {
        VStack {
            Text("The count is: \(store.state.count)")
            Button(
                action: {
                    // Send `.increment` action to store,
                    // updating state.
                    store.send(.increment)
                },
                label: {
                    Text("Increment")
                }
            )
        }
    }
}
```

## State, updates, and actions

A `Store` is a source of truth for application state. It's an [@Observable](https://developer.apple.com/documentation/observation), so you can use it anywhere in SwiftUI that you would use an observable model.

Store exposes a single observed property, `state`, which represents your application state. `state` can be any `@Observable` type that conforms to `ModelProtocol`.

`state` is read-only, and it's best practice to mark your model properties read-only too, so they can't be updated directly. Instead, all state changes are performed by an update method that you implement as part of `ModelProtocol`.

```swift
@Observable
class AppModel: ModelProtocol {
    var count = 0

    /// Update method
    /// Modifies state and returns any side-effects
    func update(
        action: AppAction,
        environment: AppEnvironment
    ) -> Fx<AppAction> {
        switch action {
        case .increment:
            self.count = self.count + 1
            return Fx.none
        }
    }
}
```

The `Fx` returned is a small struct that contains side-effects, modeled as async closures (more about that in a bit).

## Effects

Store updates are also able to produce asynchronous side-effects. These side-effects are modeled as a value type called `Fx` which contains an array of async closures to be performed by the store. The closures do some async work and return an action, which is fed back into the store. This gives you a deterministic way to schedule side-effects such as HTTP requests or database calls, in response to actions.

You can create one or more side-effects with each update, or you can perform no side-effects at all by returning `Fx.none`.

One common way to perform side-effects is by exposing services or methods on the environment passed to the update method.

```swift
/// Update method
/// Modifies state and returns any side-effects
func update(
    action: AppAction,
    environment: AppEnvironment
) -> Fx<AppAction> {
    switch action {
    case .authenticate(Credentials):
        return Fx {
          try {
            let response = try await environment.authenticate(credentials)
            return AppAction.succeedAuthentication(response)
          } catch {
            return AppAction.failAuthentication(error)
          }
        }
    }
}
```

Store performs the returned effect(s) using an internal effect runner actor, ensuring that the effects are run as tasks off the main thread. When an effect completes, the action it produces is piped back into the store, producing a new state update.

Tip: environments and their services are often also defined as [actors](https://developer.apple.com/documentation/swift/actor). This has the advantage of ensuring their work happens off the main thread.

## Getting and setting state in views

There are a few different ways to work with Store in views.

`Store.state` lets you reference the current state directly within views.

```swift
Text(store.state.text)
```

`Store.send(_)` lets you send actions to the store to change state. You might call send within a button action or event callback, for example.

```swift
Button("Set color to red") {
    store.send(AppAction.setColor(.red))
}
```

## Bindings

`StoreProtocol.binding(get:tag:)` lets you create a [binding](https://developer.apple.com/documentation/swiftui/binding) that represents some part of a store state. The `get` closure reads the state into a value, and the `tag` closure wraps the value set on the binding in an action. The result is a binding that can be passed to any vanilla SwiftUI view, changing state only through deterministic updates.

```swift
TextField(
    "Username"
    text: store.binding(
        get: { state in state.username },
        tag: { username in .setUsername(username) }
    )
)
```

## Creating scoped child components

We can also create `ViewStore`s that represent just a scoped part of the root store. You can think of them as being like a binding, but they expose a `StoreProtocol` interface, instead of a binding interface. This allows you to create apps from free-standing components that all have their own local state, actions, and update functions, but share the same underlying root store.

Imagine we have a SWiftUI child view that looks something like this:

```swift
enum ChildAction {
    case increment
    // ...
}

@Observable
class ChildModel: ModelProtocol {
    private(set) var count: Int = 0

    func update(
        action: ChildAction,
        environment: Void
    ) -> Fx<ChildAction> {
        switch action {
        case .increment:
            self.count = self.count + 1
            return Fx.none
        }
    }
}

struct ChildView: View {
    var store: ViewStore<ChildModel>

    var body: some View {
        VStack {
            Text("Count \(store.state.count)")
            Button(
                "Increment",
                action: {
                    store.send(ChildAction.increment)
                }
            )
        }
    }
}
```

Let's integrate this child component within a larger parent component. We can call `store.viewStore(get:tag:)` method to create a scoped ViewStore from our root store.

```swift
enum AppAction {
    case child(ChildAction)
    // ...
}

struct ContentView: View {
    @State private var store: Store<AppModel>

    var body: some View {
        ChildView(
            store: store.viewStore(
                // Get the child state from the parent state
                get: { state in state.child },
                // Map the child action to a parent action
                tag: { action in AppAction.child(action) }
            )
        )
    }
}
```

Note that `.viewStore(get:tag:)` is an extension of `StoreProtocol`, so you can call it on `Store` or `ViewStore` to create arbitrarily nested components!

Next, we want to integrate the child's update function into the parent update function. We forward down any actions we want the child to handle, and then tag its return `Fx` to transform the actions it produces to parent actions. 

```swift
enum AppAction {
    case child(ChildAction)
}

@Observable
class AppModel: ModelProtocol {
    private(set) var child = ChildModel()

    func update(
        action: AppAction,
        environment: AppEnvironment
    ) -> Fx<AppAction> {
        switch {
        case .child(let action):
            return child.update(
                action: action,
                environment: ()
            )
            .tag({ action in AppAction.child(action) })
        // ...
        }
    }
}
```

And that's it! We have successfully created an isolated child component and integrated it into a parent component. This tagging/update pattern also gives parent components an opportunity to intercept and handle child actions in special ways.