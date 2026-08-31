# Distributed

Distributed computing with actors.

Swift has built-in support for building distributed systems using the actor model.

The *Distributed* module extends Swift's "local" actor model,
providing the ability to natively express
that a piece of code may not be located in
the same process as the calling code.
This is expressed using the `distributed` keyword,
which can be used with actor and function declarations.

Similar to actors, they make use of actor isolation,
however unlike them,
they must assume that a distributed actor
may actually be located on a different host,
and therefore are slightly more restrictive in isolation checking
than plain actors.

An instance of distributed actor type is ---
at compile time ---
assumed to be "potentially remote",
meaning that strong isolation checks
are applied to accesses performed on it,
and only `distributed` methods may be called on it.

> Note: Swift's distributed actor model
> features an unique bring-your-own-runtime approach,
> meaning that there exist various specialized transport implementations
> (distributed actor systems)
> which are specialized for specific transports
> (e.g. network, ipc, ...)
> or use-cases,
> which all utilize the shared conceptual programming model.

## Thinking in Distributed Actors

Building distributed systems is a complex task
that requires careful consideration of
reliability, maintainability, and scalability.
There are various approaches to build such systems,
and Swift,
as a general-purpose language,
offers tools for this, such as actors.
However, in order to build distributed systems successfully
with these tools,
you will need to get into the right mindset.

You can use distributed actors,
to break up your program into
isolated, independent pieces of code,
which may be located on different processes or hosts at runtime.
This extends the notion of isolation that actors offer
from just a concurrency perspective,
to a stronger notion of isolation called "_location transparency_".

Distributed actors are location transparent,
in the sense that by looking at a distributed actor value in code,
you don't know if it is located
on the same or on some different process or host.
This allows structuring your application in a way
which mixes distributed actor instances
located on the same and on different locations in the same code.

Location transparency also
makes unit-testing distributed algorithms much simpler,
as the same distributed system
can be executed in a local-only unit-test simulation,
without having to involve actual networking.

While distributed actors make calling methods
(i.e. sending messages to them)
on _potentially remote_ actors simple and safe.
It is important to stay in the mindset of
"what should happen if this distributed actor were indeed remote...?"

Distribution comes with
the added complexity of _partial failure_ of systems.
Messages may be dropped as networks face issues,
or a remote call may be delivered (and processed!) successfully,
while only the reply to it
may not have been able to be delivered
back to the caller of a distributed function.
Swift helps you to remember about those issues
by making distributed methods implicitly `async` and `throws`
whenever an invocation is crossing a potential network boundary.

## Distributed actors

Like <doc:Concurrency#Actors> and classes,
distributed actors are reference types.
So all semantics of reference types explained in
<doc:ClassesAndStructures#Classes-Are-Reference-Types>
apply to distributed actors as well.

Distributed actors can be declared
by importing the `Distributed` module,
and prefixing the actor keyword with the `distributed` modifier.
For example,
let's declare a `GameLobby` actor,
which can handle various players registering for a game of chess
in the lobby:

```swift
import Distributed

distributed actor GameLobby {

  typealias ActorSystem = LocalTestingDistributedActorSystem

  let name = "Chess Lobby #1"
  var players: Set<Player> = []
}
```

The `ActorSystem` typealias
declared inside the distributed actor,
defines what
[`DistributedActorSystem`](https://developer.apple.com/documentation/distributed/distributedactorsystem)
the actor is intended to work with.
Declaring this is not optional,
as every distributed actor
must be associated with some distributed actor system it belongs to.

The type of actor system
describes general semantic expectations
and is usually tied to a specific transport mechanism.
It also defines a `SerializationRequirement`
which is the type that will be used in
checking distributed method declarations,
that we'll discuss in depth when talking about
<doc:Distributed#Distributed-Methods>.

### Module-wide default actor system typealias

Instead of declaring the
`typealias ActorSystem = SomeSystem`
in every distributed actor you declare,
we can instead declare a module-wide
`DefaultDistributedActorSystem` typealias instead.

Generally it is recommended
to keep that alias at the default (module wide) access control level,
like this:

```swift
import Distributed
import SomeDistributedSystem // just an example package

typealias DefaultDistributedActorSystem = SomeDistributedActorSystem
```

This way,
you no longer need to declare the `ActorSystem` alias
every time you declare an actor:

```swift
import Distributed
import SomeDistributedSystem // just an example package

typealias DefaultDistributedActorSystem = SomeDistributedActorSystem

distributed actor Worker {
  // no ActorSystem typealias necessary!
}
```

When mixing multiple actor systems in a single module,
you can either switch to
always declaring the `ActorSystem` explicitly,
or you can declare a default system,
and configure the "other" system
only for a few specific actors, like this:

```swift
import Distributed
import DistributedWebSockets // just an example package
import SomeDistributedSystem // just an example package

typealias DefaultDistributedActorSystem = SomeDistributedActorSystem

distributed actor Worker {
  // no ActorSystem typealias necessary!
}

distributed actor WebSocketWorker {
  typealias ActorSystem = SampleWebSocketActorSystem // some other actor system
}
```

This way we're able to have most of our distributed actors use one system,
but some of them are actually using a different one.
This may happen 
when we're building a more advanced application
which uses different transport mechanisms,
like websockets to communicate with client apps,
but also clustering or some other process isolation mechanism
within the server-side application itself.

You can also use typical Swift techniques such as protocols or conditional extensions 
to provide some specific actor system for some kinds of actors if you wanted to:

```swift
protocol WebSocketActor where ActorSystem == ExampleWebSocketActorSystem {}

distributed actor WSWorker: WebSocketActor {} // uses ExampleWebSocketActorSystem
```

Distributed actors implicitly conform to the
[`DistributedActor`](https://developer.apple.com/documentation/distributed/distributedactor)
protocol, which is similar to the `Actor` protocol
that `actor` declarations conform to:

```
distributed actor Worker { 
  typealias ActorSystem = LocalTestingDistributedActorSystem 
}

func check(actor: some DistributedActor) { ... }

let system = LocalTestingDistributedActorSystem()
check(actor: Worker(actorSystem: system)) // ok
```

### Distributed Actor Isolation

Since a distributed actor instance
may be located on the same,
or on a different host than the calling code,
Swift enforces additional isolation rules
in addition to those enforced for all <doc:Concurrency#Actors>.

We can learn about this
by attempting to access distributed actor-isolated state
(e.g. the `players` property)
of the `GameLobby` that we've declared earlier.
From the perspective of other code in the system,
we do not know if the game lobby
is located on the same or on a different host,
and therefore Swift will prevent us
from accessing the actor's state directly:

```swift
let lobby = GameLobby(actorSystem: actorSystem)

await lobby.players // error: distributed actor-isolated property 'players' can not be accessed from a non-isolated context
// note: access to property 'players' is only permitted within distributed actor 'GameLobby'
```


Furthermore,
if the game lobby had declared some member functions,
those will also not be accessible in cross-actor:

```swift
extension GameLobby {
  func getIdlePlayers() -> Set<Player> {
    // return only players not currently participating in a game
  }
}
```

Attempts to invoke such function
will result in a distributed actor-isolation violation,
like this:

```swift
let lobby: GameLobby = ...
await lobby.getIdlePlayers() // error: only 'distributed' instance methods can be called on a potentially remote distributed actor
```

All this strict distributed actor isolation checking
is enforced by the compiler
in order to allow us to use local as well as remote references
of the same actor type in the same way.

Non-distributed methods and distributed actor isolated state
can be accessed from the actor itself.
Or in other words, they are possible to be invoked on an `isolated` instance of a distributed actor,
which is guaranteed to be a local reference (i.e. located in the same process as the caller).

It is not possible to obtain an `isolated` remote actor reference.

It is possible
to _dynamically_ check a distributed actor reference,
for whether or not it is local,
and obtain an `isolated` reference
in order to access non-distributed methods and state on it
using the `whenLocal` method
that exists on every `distributed actor`:

```swift
let lobby: GameLobby = ...

await lobby.whenLocal { (l: isolated GameLobby) in
  lobby.players // can inspect isolated state
}
```

Distributed actors cannot declared `nonisolated` *stored* properties,
as it is not possible to implement such property
for the case when such actor is "remote".

Distributed actors can declare `nonisolated` computed properties and functions,
and those work the same way as they would on normal actors,
meaning that they cannot access any of the actor's isolated state.
In the case if a distributed actor,
this effectively means that they can only access
the `actorSystem` and `id` synthesized non-isolated properties of the actor,
or any other nonisolated declarations on the actor.

## Distributed Methods

You may make a normal actor method declaration into a distributed method
by prefixing the `func` keyword with the `distributed` contextual keyword,
similar as one prefixes an `actor` to obtain a `distributed actor`.

Only distributed actors are allowed to declare distributed methods,
and they must be instance methods
(i.e. `static` distributed methods are not allowed).
Computed read-only properties may also be distributed,
and function effectively the same as if
they were no argument taking distributed methods.
However, writable computed properties are note allowed,
similar to how actors cannot declare writable asynchronous
properties.

```swift
distributed actor GameLobby {

  var players: Set<Player> = []

  distributed func hasJoined(player: Player) -> Bool {
    self.players.contains(player)
  }
      
  distributed func join(player: Player) async throws {
    if players.insert(player) {
      try await player.greet("Welcome to the game lobby \(name), current players: \(players.count)")
    } else {
      try await player.greet("Welcome back!")
    }
  }

  distributed var lobbyName: String {
    self.name
  }
}
```

Distributed methods may be called on distributed actor instances at any time,
even as (or rather, especially when) the actor is potentially remote.

Distributed method invocations are implicitly asynchronous,
same as usual actor calls,
when performed cross actor.
Unlike plain actor methods,
they are also implicitly throwing when the potential of
crossing a network boundary via such call exists, e.g.:

```swift
let lobby: GameLobby = ...
let somePlayer: Player = ...

// potentially remote call, thus implicitly throwing and asynchronous:
try await lobby.hasJoined(player: somePlayer)
```

It is useful to see in Swift source
that those are the functions that may be invoked remotely,
as potentially we may need to apply
additional authentication or access control on such functions,
because they are serving as "entry points" to our service,
and therefore are a great spot place to centralize any additional checks.

Distributed functions are also
subject to additional type-system restrictions,
that don't apply to normal functions.
For example,
distributed functions cannot accept closures,
or parameters of types that do not conform to the actor system's stated serialization requirement (usually `Codable`).

The serialization requirement of such methods
is checked by the compiler
by checking all parameters and result type of functions
against the actor system's `SerializationRequirement` associated type,
and as a distributed actor must always
declare an actor system it can be used with,
Swift can always check this requirement.
This prevents us from
accidentally causing runtime failures
when serialization would fail handling some type at runtime,
and instead informs us about these issues earlier,
at compile time.

Most systems generally default to offering a
[`Codable`](https://developer.apple.com/documentation/swift/codable)
based serialization implementation,
and would therefore declare this requirement as `any Codable`.
For example, the [`LocalTestingDistributedActorSystem`](https://developer.apple.com/documentation/distributed/localtestingdistributedactorsystem), 
which ships with the `Distributed` module, 
uses `any Codable` as it's serialization requirement.
If we were to introduce a function
that has some not-`Codable` parameters,
while using a `Codable` based distributed actor system,
we would see the following errors:

```swift
distributed actor GameLobby {
  // typealias ActorSystem = LocalTestingDistributedActorSystem

  distributed func cantAccept(value: NotCodableValue) { /* ... */ }
  // error: parameter 'value' of type 'GameLobby.NotCodableValue' in distributed instance method does not conform to serialization requirement 'Codable'

  distributed func computeValue: NotCodableValue { /* ... */ }
  // error: result type 'GameLobby.NotCodableValue' of distributed property 'computeValue' does not conform to serialization requirement 'Codable'
}
```

The solution here is to ensure
that values we need to pass to, or return from, distributed methods,
do conform to `Codable`
(or a different protocol,
if the system we're using requires a different one).

> Note:
> Distributed actors
> can use any kind of serialization mechanism,
> including third party serialization libraries,
> as long as the actor system expresses that requirement
> and implements the serialization accordingly.
> Actor systems are not constrained to be using `Codable`,
> however it is a nice default mechanism
> as it's Swift's native serialization mechanism.

### Implicit Effects of Distributed Methods

Now what we know how to declare distributed functions,
and what restrictions then enforce on their declaration sites,
let's discuss the use sites of distributed methods.

A distributed method invocation
is inherently a call that may be crossing a network or process boundary.
Therefore,
distributed method invocations are implicitly
asynchronous _and_ throwing when invoked cross actor.

This is similar to how local-only actor method invocations
are implicitly asynchronous:

```swift
actor Score {
  var count: Int
  func increment(by points: Int) {
    precondition(points >= 0)
    self.count += points
  }
}

distributed actor DistributedScore {
  var count: Int

  distributed func increment(by points: Int) {
    precondition(points >= 0)
    self.count += points
  }
}
```

The above two "score" actors handle the same task,
of incrementing a managed score counter.
The `Score` actor is local-only,
and while the method is not declared as `async`,
calling it cross-actor will result in it being implicitly asynchronous,
and forcing us to annotate the call with an `await`
to acknowladge  the potential suspension point:

```swift
func testLocal(score: Score,
               distributedScore: DistributedScore) async throws {
  await score.increment(by: 10) // implicitly async
  try await distributedScore.increment(by: 10) // implicitly async throws
}
```

As we can see,
an cross-actor call to an actor function
caused an implicit `async` effect,
while the same type of call to a `distributed func`
caused an additional `throws` effect
that needed to be handled with a `try`.
Since the method `increment(by:)` itself
is not declared throwing by itself,
we know that the only way this method can fail,
is by the underlying transport mechanism failing in some way.

> Note:
> Exact transport semantics
> can vary between actor system implementations,
> so you should consult the documentation
> of the `DistributedActorSystem` your actor is using
> to get a complete picture of its failure handling semantics.

### Dynamically obtaining a local distributed actor reference

We have discussed that distributed actors are able to uphold their location transparency 
and programming model due to the fact that they always seem "potentially remote", 
and therefore always apply the distributed isolation checks even if the underlying instance
is actually located in the same process (i.e. "local").

This is important because it allows us to use and test the same code paths using either local
or remote instances. For example we can test a complex distributed computation using just local
actor instances in an unit test, and we know for certain it will work the same way with remote references.
We can even inject faults and problems in the local testing, however that's a topic for a later discussion.

Sometimes however we truly need to peek through the strict isolation rules and if an distributed actor 
truly was "local" access it as-if it was a normal `actor`, omitting the distributed isolation checks. This need
arises frequently during testing when we'd like to inspect if the actor  has achieved some expected state.
While we could introduce new distributed methods to expose this state for testing, this isn't recommended 
because we would have increased the service API of the actor and could potentially leave more distributed entry points
in the production system than we intended to. Another reason to not do expose more distributed methods with
the only purpose of testing is that perhaps the state we want to assert on isn't serializable, and should not be, 
so we would be working around the safety properties the system provides us only in order to write the test.

Instead, we can use the `whenLocal`method–available on any distributed actor–
to obtain an `isolated` instance to an actor, on which we're able to then
write assertions and call non-distributed methods:

```swift
distributed actor DistributedScore {
  var count: Int

  distributed func increment(by points: Int) {
    precondition(points >= 0)
    self.count += points
  }
}

func test(score: DistributedScore) async throws { 
  try await score.increment(by: 10)

  let count: Int? = await score.whenLocal { score in 
    score.count // allowed to access non-distributed methods/properties
  }
  
  assert(count == 10)
}
```

The [`whenLocal(_:)`](https://developer.apple.com/documentation/distributed/distributedactor/whenlocal(_:)) method is asynchronous because, if the actor is indeed a local reference,
it performs performs a hop to the target actor's execution context and runs the passed in closure.
It is able to return internal state of the actor and this way we can then write an assertion outside of the 
actor's execution context.

If the actor would have been remote, the `whenLocal` call will not invoke the passed in closure,
and instead will return `nil`, signaling to the caller that the instance was actually remote and that the passed closure was not executed.

### Conforming to Protocols with Distributed Actors

Protocols are one of Swift's more powerful ways to abstract and reuse logic.

Distributed actors behave very similar to actors with regards to protocol conformances.
Their implicit effects cause certain limitations to what protocols they can conform to.

For example **TODO**

```swift
import Distributed 

typealias DefaultDistributedActorSystem = 
  LocalTestingDistributedActorSystem

protocol Score {
  func increment(by points: Int)
}


protocol ScoreAsync {
  func increment(by points: Int) async throws
}

distributed actor DistributedScore: Score { 
    var count: Int = 0
    func increment(by points: Int) {

    }
}
```

TODO: complete this

## Distributed Actor Initialization

Distributed actors are created
the same way as other reference types in Swift,
however they _must_ initialize the implicit `actorSystem` property
that is synthesized for every concrete distributed actor type.

The default initializer,
i.e. the one synthesized
if there isn't an initializer declared explicitly,
is declared as accepting an `actorSystem` of the `ActorSystem` type
that the actor is associated with.
This initializer effectively assigns the actor system to self
and therefore readies the actor
with the distributed actor system:

```swift
distributed actor Player {
  // synthesized:
  // let actorSystem: ActorSystem // synthesized property
  // let id: ActorSystem.ActorID

  // synthesized:
  // init(actorSystem: ActorSystem) {
  //   self.actorSystem = actorSystem
  //   self.id = actorSystem.assignID(Self.self)
  // }
}
```

When declaring a custom initializer
the actor system property must be initialized explicitly:

```swift
distributed actor Player {
  // synthesized:
  // let actorSystem: ActorSystem // synthesized property
  // let id: ActorSystem.ActorID

  let name: String

  init(name: String, actorSystem: ActorSystem) {
    self.name = name
    self.actorSystem = actorSystem
    // synthesized: self.id = actorSystem.assignID(Self.self)
  }
}
```

In this initializer,
we accept an actor system as a parameter,
and initialize the synthesized property
as well as the name property.
The `id` property must not, and cannot,
be initialized by user code,
and will always be handled by a synthesized call
to the actor systems ID assignment method.

## Resolving Distributed Actors

While creating a local instance of a distributed actor
is exactly the same as with other objects in Swift,
obtaining a reference to a remote distributed actor
(i.e. a local actor instance,
located on a different process or host than the caller),
takes a slightly different form than just creating an instance.

In order to obtain a reference
to a (potentially) remote distributed actor,
we can use the static  `resolve` method,
defined on every distributed actor type:

```swift
distributed actor Player {
  typealias ActorSystem = MyActorSystem
}

let system: MyActorSystem
let playerID: Player.ID = /* obtained using some discovery mechanism */

let player: Player = try Player.resolve(id: playerID, using: system)
```

This allows us to obtain a reference to a `Player` actor
by asking the provided actor system to create a reference.

The actor system may return a local or remote reference,
however it should not perform asynchronous work
such as trying to confirm if the actor exists remotely or not.
The resolve method should quickly return
either a known local actor identified by the passed `id`
or a remote reference if the actor may exist remotely.

> Note:
> The reason for the "may exist remotely" semantics
> of the resolve method
> is that many systems employ creating actors on-demand,
> on the first time a request appears
> targeted towards a specific actor.

The resolve method is allowed to throw
if the passed `id` is illegal,
or otherwise known to never yield a correct reference.
For example,
if the `ID` contains enough information
to know that it is actually a local reference,
but the system is unable to map this id to a known local actor,
it is allowed to throw and fail the resolution.

It should be noted that `resolve(id:using:)`
is a fairly low level method used to create proxy objects,
and actor system libraries may choose
to provide higher level "find an actor" methods
using their own built-in  discovery mechanisms -
refer to the actor system's documentation
that you are using for specific guidance.

### Resolvable Distributed Actor Protocols (Client/Server applications)

Previous examples mostly used
the concrete distributed actor type
on both sides of a connection,
this is a common scenario
when building peer-to-peer systems
where all nodes of a distributed system
are running the same, or mostly equivalent, application code.
This is useful when building systems
which load balance workloads across a cluster,
or building peer-to-peer games
where all participants share the same code,
but have local parts,
for example every player in a game
has some local state that is unique to them,
but the general logic and types involved in the game
may be shared between all peers.

The situation changes when building client/server applications,
or otherwise asymmetric systems
where some nodes have code which others do not.
Specifically,
a "server" may have implementation logic for a `GameSession`
while clients which host only `Player` distributed actors,
do not (and should not!) have the GameSession logic,
as it is intended to be only running on the "server" hosting the game.

In order to facilitate such client/server split,
we'll have to introduce a `protocol` for the `GameSession`,
which client systems are aware of,
and have it be implemented only in the server component.

Let us define the game session protocol like this:

```
import Distributed

@Resolvable
public GameSession: DistributedActor where ActorSystem: DistributedActorSystem<any Codable> {
  distributed func makeMove(player: Player, move: GameMove) async throws -> GameMoveResponse
}
```

Let's say we implement the game session
in a way where players are not connected directly to each-other,
but instead have to send their moves to the central server.
The server's game session validates the move and forwards it to the opponent.
For a simple turn-based game like chess
this could be a simple way of modeling this interaction:

```swift
import GameService

distributed actor GameSessionImpl: GameSession {
  var players: Set<Player> = [] // players are distributed actors to which the server maintains connections
  var state: GameState

  distributed func makeMove(player: Player, move: GameMove) async throws -> GameMoveResponse {
    if let illegalMove = state.validateMove(player, move) {
      // we return some well typed representation of an illegal move,
      // rather than throwing untyped errors
      return .illegalMove(illegalMove)
    }

    let moved = state.applyMove(player, move)
    try await opponent(of: player).opponentMoved(opponent: player, move)

    return .ok(moved)
  }
}
```

In order to facilitate this shared-protocol but separate implementations,
you would organize your distributed types into


## Common Distributed Actor Patterns

The following section features some common situations, and patterns
to use when you encounter them,
while working with distributed actors.
The distributed programming paradigm
sometimes requires a certain way of re-thinking of a problem,
and the following examples should help you shift your thinking
if you find yourself unsure how to handle a situation
while moving from local-only programming,
to adopting distributed actors.

### Distributed actors generic over Actor Systems

It is possible to declare a distributed actor
with a generic actor system, however when doing so,
it must declare a concrete `SerializationRequirement`
that the actor system must require
in order for this distributed actor to be compatible with it.

For example,
if we were to implement a distributed actor
representing some common distributed algorithm,
or just some simple computation like a `Greeter`,
which does not rely on an specific transport specifics,
we may declare it as follows:

```swift
distributed actor Greeter<ActorSystem>
  where ActorSystem: DistributedActorSystem<any Codable> {
  distributed func greet(name: String) -> String {
    "Hello \(name)!"
  }
}
```

While the `ActorSystem` remains generic,
we did have to specify what
[`SerializationRequirement`](https://developer.apple.com/documentation/distributed/distributedactorsystem/serializationrequirement)
the system should be using.
This is necessary
for the type-checking of distributed functions to remain in-tact,
and prevents any attempts of using
distributed actors with actor systems
which cannot serialize
all of their method's required parameter and result types.

### Emulating callbacks

While in-process actors
are able to send and work with closures,
this is not possible with distributed actors,
as a closure cannot be serialized over the network.
This is one difference in programming
for distribution as opposed to local-only concurrency with actors.

Let us consider the following "call me later" example
expressed in pure local actors:

```swift
actor Alice {
  func call(later: @Sendable (String) -> ()) async -> String {
    Task.detached {
      // do some asynchronous processing AFTER returning from the 'call' method...
      later("Here's the info you asked for!")
    }

    return "Thanks for your call!"
  }
}
```

```swift
actor Bob {
  func test(alice: Alice) async {
    let immediateReply = await alice.call { laterReply in
      print("later: \(laterReply)")
    }

    print("immediately: \(immediateReply)")
  }
}

// OUTPUT:
// immediately: Thanks for your call!
// later: Here's the info you asked for!
```

This example models a situation
where we call the `Alice` actor,
and receive a reply immediately,
but at the same time we registered a closure
to be called at some later point in time
when some additional information was looked up by the actor.
In local-only actors,
a common way of modeling this is passing a closure to the actor.

In distributed actors,
the same can be achieved using distributed method calls
rather than closures, like this:

```swift
protocol InfoListener: DistributedActor, Codable {
  distributed func additionalInfo(_ info: String)
}

distributed actor Alice {
  distributed func call(later: some InfoListener) async -> String {
    Task.detached {
      // do some asynchronous processing AFTER returning from the 'call' method...
      try await later.additionalInfo("Here's the info you asked for!")
    }

    return "Thanks for your call!"
  }
}
```

So instead of a closure,
the `Alice` distributed actor is now accepting an `InfoListener`,
which we'll implement
using a distributed actor on the calling side
by having Bob be a distributed actor
and conform to this protocol:

```swift
distributed actor Bob {
  func test(alice: Alice) async {
    let immediateReply = try await alice.call(self)

    print("immediately: \(immediateReply)")
  }
}

extension Bob: InfoListener {
  distributed func additionalInfo(_ info: String) {
    print("later: \(info)")
  }
}


// OUTPUT:
// immediately: Thanks for your call!
// later: Here's the info you asked for!
```

You may also create an per-request actor,
rather than having Bob conform to this protocol.
Using a per-call actor is equivalent to
using the closure callback from the initial example,
because we can capture
any additional state we'd like to associate the reply with, like this:

```swift
distributed actor Bob {
  func test(alice: Alice) async {
    // We have to make sure, in some way, that the `DistributedCallback` instance stays alive to receive the callback
    let immediateReply = try await alice.call(later: DistributedCallback(name: "Bob", actorSystem: self.actorSystem))

    print("immediately: \(immediateReply)")
  }
}

distributed actor DistributedCallback: InfoListener {
  distributed func additionalInfo(_ info: String) {
    print("later(\(name)): \(laterReply)")
  }
}


// OUTPUT:
// immediately (first): Thanks for your call!
// later (first): Here's the info you asked for!

// immediately (second): Thanks for your call!
// later (second): Here's the info you asked for!
```



<!-- TODO: Implementing your own actor system as an article in API docs -->



<!--
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
-->
