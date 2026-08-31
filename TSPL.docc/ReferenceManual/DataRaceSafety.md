# Data-Race Safety

Eliminate data races at compile time.

The Swift 6 language mode eliminates data races at compile time by
identifying and diagnosing risk of concurrent access to shared state.

## Data Isolation

Swift understands and verifies the safety of all mutable state in your code.
When you share values between concurrent code, Swift ensures that the value
is either safe to share, or that it is only accessed by one task at a
time. This guarantee is called _data isolation_, and it maintains
mutually exclusive access to mutable state at compile time.
For an overview of isolation in Swift, see <doc:Concurrency#Isolation>.

### Isolation Domains

Every declaration in Swift code has a specific isolation domain. There
are three kinds of isolation domains:
1. Non-isolated
2. Isolated to an actor instance
3. Isolated to a global actor

Tasks and actors provide isolation domains, and mutable state must
only be accessed from one isolation domain at a time.
You can send mutable state from one isolation domain to another,
and Swift ensures that mutable state is not accessed from multiple
isolation domains at once.

### Non-isolated

A non-isolated declaration can run in any isolation domain.
Non-isolated code can run directly on an actor, or it can run
outside of any actor.

You specify that a declaration is non-isolated with the `nonisolated`
keyword. Swift guarantees that non-isolated declarations are safe
to call from anywhere by ensuring that they do not access actor-isolated
state in their implementation. Non-isolated functions safely call other
non-isolated functions and access non-isolated variables.

For example, the following code contains a `nonisolated` function that
accesses an actor-isolated variable, which results in an error:

```swift
@MainActor var globalCounter = 0

nonisolated func incrementCounter() {
    globalCounter += 1 // Error
}
```
Type declarations can be marked with `nonisolated`, which causes Swift
to infer that all properties and methods of the type are `nonisolated`
by default.
Non-isolated variables are safe if they cannot be mutated concurrently.
It is safe to mark a variable as non-isolated in the following cases:

1. The variable is a `let`-constant with a type that conforms to `Sendable`.
2. The variable is a property of a non-`Sendable` type.
3. The variable is a property of a struct and the type of the property
   conforms to `Sendable`.

Extensions be marked with `nonisolated`, which promptes Swift to infer
that all properties and methods inside the extension are `nonisolated`
by default.

#### Non-isolated Asynchronous Functions

Asynchronous functions always run on an _executor_, which is a service
that can run the synchronous pieces of an asynchronous function. Each actor
instance has a serial executor that runs functions on the actor. The
concurrency library also provides a global concurrent executor, which runs
asynchronous functions on the concurrent thread pool.

A non-isolated asynchronous function can either run on the actor that
calls it, or it can switch off of the actor to run on the global
concurrent executor.

A non-isolated asynchronous function that runs on the caller's actor is
deonated with the `nonisolated(nonsending)` keyword:

```swift
class NotSendable {
  nonisolated(nonsending)
  func performAsync() async { ... }
}
```

Async functions can be declared to always switch off of an actor to run using
the `@concurrent` attribute:

```swift
struct S: Sendable {
  @concurrent
  func alwaysSwitch() async { ... }
}
```

The implementation of an `@concurrent` function will always switch off
of an actor before running the function body. Only non-isolated functions
can be `@concurrent` functions, and marking a function with `@concurrent`
implies `nonisolated`.

`nonisolated(nonsending)` is the default behavior of non-isolated
asynchronous functions when the `NonisolatedNonsendingByDefault`
upcoming feature flag is enabled.
`@concurrent` is the default behavior of non-isolated
asynchronous functions when the `NonisolatedNonsendingByDefault`
upcoming feature flag is not enabled.

### Actors

Actors give you a way to define a custom isolation domain.
Actor-isolated methods must only run on the actor, and
mutable state in an actor must only be accessed within
actor-isolated methods.
For an overview of actors, see <doc:Concurrency#Actors>.

All stored properties of an actor are isolated to the `self` instance
of the actor. Methods of an actor are isolated to the `self`
parameter, and can synchronously access the actor's isolated
properties and other isolated methods.
A method of an actor can be marked as `nonisolated`, and Swift will
prevent synchronous access to actor-isolated properties.

Actor types conform to `Sendable` implicitly. You can pass a reference
to an actor to a different actor or a concurrent task. Swift ensures
that access to actor-isolated state only happens within the actor. You
can access `nonisolated` properties and methods from outside the actor,
but access to isolated properties and methods must be done asynchornously.

### Global Actors

A global actor is a singleton actor that can be expressed using
a custom attribute.
For an overview of global actors, see <doc:Concurrency#Global-Actors>.

Like instance actors, a global-actor isolated variable or property can
only be accessed on the actor. A global-actor isolated function or method
can only run on the actor.

#### Global-Actor Isolated Types and Extensions

A global actor can be written on types and extensions. A global-actor
isolated type or extension prompts Swift to infer global-actor
isolation on all methods and properties in the type or extension.

For example, the following code contains a `Player` class that is
isolated to the main actor:

```swift
@MainActor
class Player {
    var score: Int

    func incrementScore() {
        score += 1
    }
}
```

Swift infers main-actor isolation for the `score` property and
the `incrementScore` method.

Global-actor isolated types have an implicit conformance to `Sendable`
in the following cases:
1. There is no explicit unavailable conformance to `Sendable`, including
   conformances inherited from superclasses.
2. If the type is a subclass, the superclass is either `Sendable` or isolated
   to the same global actor.

Global-actor isolated classes that inherit from non-isolated, non-`Sendable`
super classes cannot conform to `Sendable` because superclass methods
can freely access non-isolated mutable state, which is not safe to access
from outside the global actor of the subclass. For example, the following
code contains a non-isolated, non-`Sendable` class `C` with a main-actor
isolated subclass:

```swift
class C {
    var count = 0
    func incrementCount() {
        count += 1
    }
}

@MainActor
class Subclass: C {
    func incrementCountOnMain() {
        count += 1
    }
}

@MainActor
func useSubclass() {
    let subclass = Subclass()
    Task { @concurrent in
        subclass.incrementCount() // Error
    }

    subclass.incrementCount()
}
```

The above code is invalid. The non-isolated superclass property
`count` is only safe to access from one isolation domain at a time.

#### Global-Actor Isolated Function Types

A function type can be isolated to a global actor by writing the custom
attribute in the function type attribute list. Global-actor isolated
functions can capture state that is isolated to the global actor.

Functions with global-actor isolated type must always run on that global
actor. Global-actor isolated function types implicitly conform to `Sendable`.
It's safe to pass a reference to the function outside the actor, and Swift
ensures that the function is either called on the actor, or the call is
performed asynchronously.


## Isolation Inference

Swift infers global actor isolation in the code you write based on
class inheritance and protocol conformances.

### Classes

If a superclass has global actor isolation, Swift infers that global actor
on subclasses. For example, the code below has a main-actor
isolated class `Vehicle`, and a subclass `Train` that inherits
from `Vehicle`:

```swift
@MainActor
class Vehicle {
    var currentSpeed = 0.0
    func makeNoise() {
        // do nothing - an arbitrary vehicle doesn't necessarily make a noise
    }
}

class Train: Vehicle {
    override func makeNoise() {
        print("Choo Choo")
    }
}
```

In the above example, all methods and properties in `Vehicle`
are isolated to the main actor. The `Train` class inherits all
methods, properties, and global actor isolation from the `Vehicle`
superclass, so Swift infers main-actor isolation for the `makeNoise`
override.

Swift also infers global-actor isolation from individual overridden
methods. For example, the following code isolates one method of the
`Vehicle` class to the main actor instead of the entire class:

```swift
class Vehicle {
    var currentSpeed = 0.0

    @MainActor
    func makeNoise() {
        // do nothing - an arbitrary vehicle doesn't necessarily make a noise
    }
}

class Train: Vehicle {
    override func makeNoise() {
        print("Choo Choo")
    }
}
```

Swift infers main-actor isolation for the `makeNoise` override of
the `Train` subclass based on the isolation of the `makeNoise` method
in `Vehicle`.

### Protocols

Swift infers global-actor isolation from protocol conformances.
When a type conforms to a protocol, Swift infers actor isolation from
the protocol itself, and from individual protocol requirements.
For example, the following code has a main-actor isolated protocol
`Togglable`, and a conforming struct `Switch`:

```swift
@MainActor
protocol Togglable {
    mutating func toggle()
}

struct Switch: Togglable {
    var isOn: Bool = false

    mutating func toggle() {
        isOn.toggle()
    }
}
```

In the above example, `Togglable` and all of its requirements
are isolated to the main actor. Swift infers main-actor isolation
on types that conform to `Togglable`, so all methods and properties
of `Switch` are isolated to the main actor, including the `isOn`
property and the `toggle` method.

Swift only infers isolation from protocols when you write the conformance
at the primary declaration. If you write the conformance in
an extension, then isolation inference only applies to requirements that
are implemented in the extension. For example, the following code
implements a conformance of `Switch` to `Togglable` in an extension:

```swift
@MainActor
protocol Togglable {
    mutating func toggle()
}

struct Switch: Togglable {
    var isOn: Bool = false
}

extension Switch: Togglable {
    mutating func toggle() {
        isOn.toggle()
    }
}
```

Swift does not infer global-actor isolation on the `Switch` type itself;
the `Switch` type is `nonisolated`, and the methods and properties directly
inside the type are `nonisolated`. Swift infers global-actor isolation for
the protocol requirements implemented in the extension that declares the
conformance to `Togglable`, so the `toggle` method is isolated to the
main actor.

### Function Values

Swift infers isolation of function values.

The isolation of a closure can be explicitly specified with a type
annotation or in the closure signature. If no isolation is specified,
the inferred isolation for a closure depends on two factors:

1. The isolation of the context where the closure is formed.
2. Whether the type of the closure is `@Sendable` or `sending`.

By default, closures are isolated to the same context they're formed in.
For example:

```swift
@MainActor
class Model { ... }

@MainActor
class C {
    var models: [Model] = []

    func mapModels<Value>(
      _ keyPath: KeyPath<Model, Value>
    ) -> some Collection<Value> {
        models.lazy.map { $0[keyPath: keyPath] }
    }
}
```

In the above code, the closure to `LazySequence.map` has type
`@escaping (Base.Element) -> U`. This closure must stay on the main
actor where it was originally formed. This allows the closure to capture
state or call isolated methods from the surrounding context.

Closures that can run concurrently with the original context are marked
explicitly through `@Sendable` and `sending` annotations described in later
sections. Swift infers that these closures are `nonisolated` because they
may be called in any isolation domain.

For `async` closures that may be evaluated concurrently, the closure can still
capture the isolation of the original context. This mechanism is used by the
`Task` initializer so that the given operation is isolated to the original
context by default, while still allowing explicit isolation to be specified:

```swift
@MainActor
func eat(food: Pineapple) {
    Task {
        // This task is isolated to `MainActor`
        Chicken.prizedHen.eat(food: food)
    }

    Task { @MyGlobalActor in
        // This task is isolated to `MyGlobalActor`
    }
}
```

The closure's type here is defined by `Task.init`. Swift infers
the main-actor isolation for the first task because the lexical context
is main-actor isolated. The second task is explicitly isolated to
a different actor, so isolation inference does not apply.

If the enclosing context is isolated to an actor instance, Swift only
infers isolation of closures if the actor instance is captured in
the closure.

## Isolation Boundaries

Tasks can pass data into and out of different isolation domains in a
concurrent program. Values cross isolation boundaries most commonly
through asynchronous function calls that switch isolation, but they
can also cross isolation boundaries through global and static variables,
protocol conformances, subclass overrides, function conversions,
and closure captures.

Every time a value crosses an isolation boundary, Swift checks
that the value is safe to send to concurrently-executing code.

### Sendable Types

Types that are always safe to share across concurrent code
conform to the `Sendable` protocol.
For an overview of `Sendable` types, see <doc:Concurrency#Sendable-Types>.

Swift infers `Sendable` conformances for actors, global-actor
isolated types, and global-actor isolated functions.

A value type can conform to `Sendable` if all stored properties
are either:

1. Non-isolated and have `Sendable` type, or
2. Isolated to a global actor

A class type can conform to `Sendable` if:

1. Its superclass conforms to `Sendable`, and:
2. All stored properties are either:
   1. Immutable and have `Sendable` type, or
   2. Isolated to a global actor.

### Region-Based Isolation

Swift determines whether a non-`Sendable` value can be safely sent over
an isolation boundary through a flow-sensitive analysis called
_region-based isolation_.

Swift groups non-`Sendable` values into
_isolation regions_ that can only be accessed by one isolation domain
at a time. When a value is sent to another actor, all other values in
the isolation region cannot be accessed from the original context again.

```swift
// Not Sendable
class Client {
    var name: String
    var balance: Double
    init(name: String, balance: Double) {
        self.name = name
        self.balance = balance
    }
}

actor ClientStore {
    var clients: [Client] = []

    static let shared = ClientStore()

    func addClient(_ c: Client) {
        clients.append(c)
    }
}

func openNewAccount(name: String, balance: Double) async {
    let client = Client(name: name, balance: balance)
    await ClientStore.shared.addClient(client)
}
```

The above program is safe because:

* `client` does not have access to any non-`Sendable` state from its initializer
  parameters since `String`s and `Double`s conform to `Sendable`.
* `client` being newly initialized implies that `client` cannot have any uses
  outside of `openNewAccount`.
* `client` is not used within `openNewAccount` after the call to `addClient`.

If `openNewAccount` calls a method on client after the call to
`addClient`, Swift produces an error because `openNewAccount`
and the client store actor can access `client` at the same time:

```swift
func openNewAccount(name: String, balance: Double) async {
    let client = Client(name: name, balance: balance)

    await ClientStore.shared.addClient(client) // Error

    // This access can happen concurrently with other tasks
    // running on `ClientStore.shared`
    client.logToAuditStream()
}
```

#### Isolation Regions

An _isolation region_ is a set of non-`Sendable` values that can only be
referenced from values within that isolation region. An
isolation region can be part of a specific actor or task's isolation domain,
or it can be disconnected from any specific isolation domain.

Isolation regions are a conservative approximation at compile time of the
runtime object graph. Any operation that could possibly introduce a path
between two objects must consider those two objects as part of the same region
after the operation.

Two values `x` and `y` are defined to be within the same isolation region
if:

1. `x` is a reference to `y`.
2. `x` or a property of `x` might be referenceable from `y` through
   chained access of `y`'s properties.

Isolation regions are merged together when you introduce a potential
reference or access path to another value. This can happen through function
calls and assignments. Many expression forms are sugar for a function
application, including property accesses.

A function implementation can create references and access paths between
its argument and result values. By default, a function call causes all
non-`Sendable` arguments and result values to merge into one region. If
the function is isolated to an actor, the values are merged into the actor's
region. If the function is non-isolated, the values are merged into a larger
region that is disconnected from any actor.

As the program executes, an isolation region can be passed across isolation
boundaries, but an isolation region can never be accessed by multiple
isolation domains at once. When a region `R` is merged into another region
`R'` that is isolated to an actor, `R` becomes protected by
that isolation domain and cannot be passed or accessed across isolation
boundaries again.

### Cross-Isolation Function Calls

When a function call crosses an isolation boundary, Swift checks that
the argument and result values are safe to send to concurrent code.
The function call is data-race safe if for every argument and result
value, either:

1. The type of the value conforms to `Sendable`, or
2. The value is in a disconnected region.

### Global and Static Variables

You can access global and static variables from anywhere in
a program. Swift ensures that either a global variable is safe
to access concurrently, or that the variable is only accessed
from one isolation domain.

A global variable is safe from data races if one of the following
conditions applies:

1. It is a `let`-constant and the type conforms to `Sendable`
2. It is isolated to a global actor
3. It is marked with `nonisolated(unsafe)` and manually protected
   by an external synchronization mechanism.

### Protocol Conformances

Values can cross an isolation boundary through a protocol conformance.
If a protocol requirement has different isolation from the implementation
in a concrete type, then calling the requirement in generic code can cause
the argument and result values to cross an isolation boundary.

Swift ensures data-race safety for protocol requirements by ensuring that
either the implementation can run in the isolation domain of the
requirement, or the argument and result types are safe to cross over
an isolation boundary.

Given a protocol requirement `r` and an implementation `r'` in a conforming
type, the following rules apply:

* If `r` is synchronous, then `r'` is safe from data races if one of the
  following conditions applies:
  * The isolation of `r'` matches the isolation of `r'`
  * `r'` is `nonisolated`
* If `r` is asynchronous, then the implementation `r'` is safe from data
  races if one of the following conditions applies:
  * The isolation of `r'` matches the isolation of `r'`
  * `r'` is `nonisolated(nonsending)`
  * All parameter and result types conform to `Sendable`.

### Subclass Overrides

Values can cross an isolation boundary through calls to overridden
methods. If a subclass override has different isolation from the
superclass method, then calling the override through the superclass
can cause the argument and result values to cross an isolation
boundary.

The data-race safety rules for subclass overrides are the same as protocol
conformances, given a superclass method `r` and an override `r'` in a
subclass.

### Function Conversions

Function conversions can change isolation. You can think of this like a
closure with the new isolation that calls the original function,
asynchronously if necessary. For example, a function conversion from
one global-actor-isolated type to another can be conceptualized as an
async closure that calls the original function with `await`:

```swift
@globalActor actor OtherActor { ... }

func convert(
  closure: @OtherActor () -> Void
) {
  let mainActorFn: @MainActor () async -> Void = closure

  // The above conversion is the same as:

  let mainActorEquivalent: @MainActor () async -> Void = {
    await closure()
  }
}
```

A function conversion that crosses an isolation boundary must only
pass argument and result values that are `Sendable`; Swift ensures this
at the point of the function conversion. For example, converting an
actor-isolated function type to a `nonisolated` function type requires
that the argument and result types conform to `Sendable`:

```swift
class NotSendable {}
actor MyActor {
  var ns = NotSendable()

  func getState() -> NotSendable { ns }
}

func invalidResult(a: MyActor) async -> NotSendable {
  let grabActorState: nonisolated(nonsending) () async -> NotSendable = a.getState // Error

  return await grabActorState()
}
```

In the above code, the conversion from the actor-isolated method `getState`
to a `nonisolated(nonsending)` function is invalid, because the
result type does not conform to `Sendable` and the result value could be
actor-isolated state. The `nonisolated` function can be called from
anywhere, which would allow access to actor state from outside the actor.

Not all function conversions cross an isolation boundary, and function
conversions that don't can safely pass non-`Sendable` arguments and results.
For example, a `nonisolated(nonsending)` function type can always be converted
to an actor-isolated function type, because the `nonisolated(nonsending)`
function will simply run on the actor:

```swift
class NotSendable {}

nonisolated(nonsending)
func performAsync(_ ns: NotSendable) async { ... }

@MainActor
func convert(ns: NotSendable) async {
  // Okay because 'performAsync' will run on the main actor
  let runOnMain: @MainActor (NotSendable) async -> Void = performAsync

  await runOnMain(ns)
}
```

The following table enumerates each function conversion rule and specifies
which function conversions cross an isolation boundary. Function conversions
that cross an isolation boundary require `Sendable` argument and result types,
and the destination function type must be `async`. Note that the function
conversion rules for synchronous `nonisolated` functions and asynchronous
`nonisolated(nonsending)` functions are the same; they are both
represented under the "Nonisolated" category in the table:

| Old isolation        | New isolation          | Crosses Boundary |
|----------------------|------------------------|------------------|
| Nonisolated          | Actor isolated         | No               |
| Nonisolated          | `@isolated(any)`       | No               |
| Nonisolated          | `@concurrent`          | Yes              |
| Actor isolated       | Actor isolated         | Yes              |
| Actor isolated       | `@isolated(any)`       | No               |
| Actor isolated       | Nonisolated            | Yes              |
| Actor isolated       | `@concurrent`          | Yes              |
| `@isolated(any)`     | Actor isolated         | Yes              |
| `@isolated(any)`     | Nonisolated            | Yes              |
| `@isolated(any)`     | `@concurrent`          | Yes              |
| `@concurrent`        | Actor isolated         | Yes              |
| `@concurrent`        | `@isolated(any)`       | No               |
| `@concurrent`        | Nonisolated            | Yes              |

#### Non-Sendable Function Conversions

If a function type is not `@Sendable`, only one isolation domain can
reference the function at a time, and calls to the function may never
happen concurrently. These rules for non-`Sendable` types are enforced
through region isolation. When a non-`@Sendable` function is converted
to an actor-isolated function, the function value itself is merged into the
actor's region, along with any non-`Sendable` function captures:

```swift
class NotSendable {
  var value = 0
}

nonisolated(nonsending)
func convert(closure: () -> Void) async {
  let ns = NotSendable()
  let disconnectedClosure = {
    ns.value += 1
  }
  let valid: @MainActor () -> Void = disconnectedClosure // okay
  await valid()

  let invalid: @MainActor () -> Void = closure // error
  await invalid()
}
```

The function conversion for the `invalid` variable is an error because the
non-`Sendable` captures of `closure` could be used concurrently from the
caller of `convert` and the main actor.

Converting a non-`@Sendable` function type to an actor-isolated one is invalid
if the original function must leave the actor in order to be called:

```swift
nonisolated(nonsending)
func convert(
    fn1: @escaping @concurrent () async -> Void,
) async {
    let fn2: @MainActor () async -> Void = fn1 // error

    await withDiscardingTaskGroup { group in
      group.addTask { await fn2() }
      group.addTask { await fn2() }
    }
}
```

In general, a conversion from an actor-isolated function type to a
`nonisolated` function type crosses an isolation boundary, because the
`nonisolated` function type can be called from an arbitrary isolation domain.
However, if the conversion happens on the actor, and the new function type is
not `@Sendable`, then the function must only be called from the actor. In this
case, the function conversion is allowed, and the resulting function value
is merged into the actor's region:

```swift
class NotSendable {}

@MainActor class C {
  var ns: NotSendable

  func getState() -> NotSendable { ns }
}

func call(_ closure: () -> NotSendable) -> NotSendable {
  return closure()
}

@MainActor func onMain(c: C) {
  // 'result' is in the main actor's region
  let result = call(c.getState)
}
```