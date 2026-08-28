# Ownership

Control how Swift copies, borrows, and consumes your values.

Every value in your program has an owner ---
the place in your code that's responsible for it.
When you pass a value to a function,
return it,
or store it in a new variable,
Swift has to decide what happens to that ownership:
Does the value get copied,
so the caller and the callee each end up with their own independent copy?
Does it get *borrowed*,
so whoever receives it can look at it
without taking responsibility for it?
Or does it get *consumed*,
so responsibility for it moves to whoever receives it,
and the original owner can't use it anymore?

For most of the code you write,
you don't have to think about these questions at all.
As you saw in <doc:ClassesAndStructures#Structures-and-Enumerations-Are-Value-Types>,
Swift's structures and enumerations are value types:
Assigning one to a new variable,
or passing it to a function,
makes an independent copy.
That copying is safe and easy to reason about,
and Swift's compiler is good at optimizing away copies
that don't actually change your program's behavior.
Combined with the exclusivity checks described in <doc:MemorySafety>,
this default gives you memory safety
without requiring you to manage ownership by hand.

Sometimes, though, copying isn't what you want.
A value might represent a resource that can't be duplicated meaningfully,
like a file that's currently open
or a slot in a fixed-size hardware buffer.
A value might be expensive to copy,
and you want precise control over when copies happen,
for performance-critical code.
This chapter describes the vocabulary and syntax
Swift gives you for those situations ---
*borrowing* and *consuming* parameters,
*noncopyable* types that opt out of copying entirely,
and *nonescapable* types whose values can't outlive
the scope that created them.

## Understanding Ownership

Think about borrowing a book from a library.
While you have it, you can read it and refer to it,
but you don't own it:
You have to give it back,
and you can't tear out its pages or give it to someone else.
Swift's *borrowing* convention works the same way.
Code that borrows a value can read it,
but the value still belongs to its original owner,
and the borrowing code has to leave it usable when it's done.

Now think about buying that same book instead.
Once you own it, you can do anything you want with it,
including passing your copy along to someone else ---
at which point you don't have it anymore.
Swift's *consuming* convention works the same way.
Code that consumes a value becomes responsible for it,
and the value's original owner can't use it again afterward.

A third convention, *mutating*,
lets code temporarily borrow a value
with permission to change it,
and then hand it back to its original owner when it's done.
You've already used this convention
every time you called a mutating method
or passed a variable as an in-out parameter ---
see <doc:MemorySafety> for more information
about how Swift keeps those accesses safe and exclusive.

Borrowing, consuming, and mutating aren't new concepts ---
they're names for conventions
that Swift's compiler already relies on internally
to decide when to copy a value,
retain or release a class instance,
or pass a value by reference.
The rest of this chapter shows you
how to make some of those decisions explicit yourself:
first for the parameters you pass to functions and methods,
and then for values whose types
opt out of copying or escaping altogether.

## Borrowing and Consuming Parameters

Consider a theater's coat check counter.
Every coat gets a ticket,
and that ticket is what lets you claim your coat later.
The following structure models a ticket like that:

```swift
struct CoatCheckTicket {
    let claimNumber: Int
}
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> struct CoatCheckTicket {
         let claimNumber: Int
     }
  ```
-->

Whenever you pass a `CoatCheckTicket` to a function,
Swift has to decide how the function receives it:
Does the function just look at the ticket,
or does it take responsibility for it?
By default, Swift's compiler answers that question for you,
and it usually picks the most efficient option automatically.
Most of the time, you don't need to think about this at all ---
but when you do want control over that decision,
you can write it explicitly using
the `borrowing` and `consuming` parameter modifiers,
in the same position where you'd write `inout`.

The following function only needs to look at a ticket,
so it marks its parameter `borrowing`:

```swift
func announce(_ ticket: borrowing CoatCheckTicket) {
    print("Now serving ticket #\(ticket.claimNumber).")
}
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> func announce(_ ticket: borrowing CoatCheckTicket) {
         print("Now serving ticket #\(ticket.claimNumber).")
     }
  ```
-->

This function that hands over the coat, on the other hand,
takes ownership of the ticket it's given ---
the customer doesn't get to reuse it afterward ---
so it marks its parameter `consuming`:

```swift
func redeem(_ ticket: consuming CoatCheckTicket) -> String {
    return "Coat retrieved for ticket #\(ticket.claimNumber)."
}
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> func redeem(_ ticket: consuming CoatCheckTicket) -> String {
         return "Coat retrieved for ticket #\(ticket.claimNumber)."
     }
  ```
-->

Both functions work the way you'd expect:

```swift
let ticket = CoatCheckTicket(claimNumber: 42)
announce(ticket)
print(redeem(ticket))
// Prints "Now serving ticket #42."
// Prints "Coat retrieved for ticket #42."
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> let ticket = CoatCheckTicket(claimNumber: 42)
  -> announce(ticket)
  -> print(redeem(ticket))
  <- Now serving ticket #42.
  <- Coat retrieved for ticket #42.
  ```
-->

Because `CoatCheckTicket` is an ordinary, copyable structure,
this example behaves the same with or without the modifiers ---
`redeem(_:)` simply receives a copy of `ticket`,
and the original `ticket` constant is still valid afterward.
Writing `borrowing` and `consuming` explicitly doesn't change
what the code is allowed to do here;
it changes how the compiler passes the value,
which can matter for performance
when a type is expensive to copy.
Later in this chapter,
in <doc:Ownership#Noncopyable-Types>,
you'll see types where this distinction
also changes what's allowed.

Both modifiers apply to methods the same way they apply to functions,
except that they describe how a method receives `self`
instead of an ordinary parameter:

```swift
extension CoatCheckTicket {
    borrowing func announce() {
        print("Now serving ticket #\(claimNumber).")
    }

    consuming func redeemed() -> String {
        "Coat retrieved for ticket #\(claimNumber)."
    }
}
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> extension CoatCheckTicket {
         borrowing func announce() {
             print("Now serving ticket #\(claimNumber).")
         }

         consuming func redeemed() -> String {
             "Coat retrieved for ticket #\(claimNumber)."
         }
     }
  ```
-->

In fact, Swift already chooses one of these two conventions
for every function, method, and initializer you write,
whether or not you write the modifier yourself.
Initializers and property setters default to `consuming`,
because their entire job is to take a value
and store it somewhere new.
Nearly everything else ---
ordinary functions, methods, and computed-property getters ---
defaults to `borrowing`,
because reading a value without taking ownership of it
is normally cheaper.
Writing the modifier explicitly doesn't usually change your program's behavior;
it documents your intent,
and it becomes required, rather than optional,
for the noncopyable types you'll meet later in this chapter.

### Making Explicit Copies

Because a `borrowing` parameter doesn't own its value,
Swift limits what you can do with it:
You can read it as many times as you like,
but you can't consume it more than once.
The following function tries to return its ticket in two places,
which means consuming it twice:

```swift
func duplicate(_ ticket: borrowing CoatCheckTicket) -> (CoatCheckTicket, CoatCheckTicket) {
    return (ticket, ticket)
}
// Error: 'ticket' consumed more than once.
```

<!--
  - test: `ownership-parameters-err`

  ```swifttest
  -> func duplicate(_ ticket: borrowing CoatCheckTicket) -> (CoatCheckTicket, CoatCheckTicket) {
         return (ticket, ticket)
     }
  !$ error: 'ticket' consumed more than once
  !! func duplicate(_ ticket: borrowing CoatCheckTicket) -> (CoatCheckTicket, CoatCheckTicket) {
  !!                  ^
  !$ note: multiple consumes here
  !! return (ticket, ticket)
  !! ^
  ```
-->

When you actually do want a copy,
you have to ask for it,
using the `copy` operator:

```swift
func duplicate(_ ticket: borrowing CoatCheckTicket) -> (CoatCheckTicket, CoatCheckTicket) {
    return (copy ticket, copy ticket)
}
```

<!--
  - test: `ownership-parameters`

  ```swifttest
  -> func duplicate(_ ticket: borrowing CoatCheckTicket) -> (CoatCheckTicket, CoatCheckTicket) {
         return (copy ticket, copy ticket)
     }
  ```
-->

This requirement is easy to miss for an ordinary copyable structure
like `CoatCheckTicket`,
because leaving out `borrowing` and `consuming` entirely
also compiles, and copies just as freely as before.
It matters most for the noncopyable types
described later in this chapter,
where there's no implicit copy to fall back on ---
the `copy` operator becomes the only way
to duplicate a value at all,
and only types that support copying allow it.

## Noncopyable Types

A `CoatCheckTicket` is supposed to represent
the sole claim to one specific coat.
But nothing about the structure from the previous section
actually enforces that ---
if Swift let you copy a ticket freely,
two different people could each hand over a copy
and both expect to walk out with the same coat.
For a type like this,
copying isn't just unnecessary, it's actively wrong.

Swift lets you rule it out entirely
by writing `~Copyable` after the type's name,
the same place you'd list a protocol it conforms to:

```swift
struct CoatCheckTicket: ~Copyable {
    let claimNumber: Int
}
```

<!--
  - test: `ownership-noncopyable`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  ```
-->

The tilde (`~`) reads as *without* ---
`~Copyable` means this type comes without the usual Copyable conformance
that almost every other type in Swift has implicitly.
<doc:Ownership#Noncopyable-Types-in-Generic-Code>
says more about why that conformance is implicit in the first place.

Once `CoatCheckTicket` is noncopyable,
Swift enforces the single-claim rule for you.
Assigning a ticket to a new constant doesn't copy it, it *moves* it,
transferring ownership away from the original constant:

```swift
func run() {
    let ticket = CoatCheckTicket(claimNumber: 42)
    let other = ticket
    print(ticket.claimNumber)
    print(other.claimNumber)
}
run()
// Error: 'ticket' used after consume.
```

<!--
  - test: `ownership-noncopyable-err`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> func run() {
         let ticket = CoatCheckTicket(claimNumber: 42)
         let other = ticket
         print(ticket.claimNumber)
         print(other.claimNumber)
     }
  -> run()
  !$ error: 'ticket' used after consume
  !! let ticket = CoatCheckTicket(claimNumber: 42)
  !!     ^
  !$ note: consumed here
  !! let other = ticket
  !!             ^
  !$ note: used here
  !! print(ticket.claimNumber)
  !!       ^
  ```
-->

The move to `other` consumes `ticket`,
so the line that prints `ticket.claimNumber` afterward is an error ---
at that point in the code, `ticket` no longer has a value.
This is also why, as you saw in the previous section,
a parameter of a noncopyable type
can't leave off the `borrowing` or `consuming` modifier:
Swift needs to know which convention applies
because there's no implicit copy to fall back on
if it guesses wrong.

Because a noncopyable value's lifetime is so precisely tracked,
these types can safely take on responsibilities
that go beyond what an ordinary structure can do.
In particular, a noncopyable structure or enumeration can declare a `deinit`,
the same kind of cleanup method you saw for classes in <doc:Deinitialization>.
Swift runs it automatically, exactly once,
at the point where a value's lifetime ends:

```swift
struct CoatCheckTicket: ~Copyable {
    let claimNumber: Int

    deinit {
        print("Filing ticket #\(claimNumber) in the used-ticket bin.")
    }
}

func run() {
    let ticket = CoatCheckTicket(claimNumber: 7)
    print("Holding ticket #\(ticket.claimNumber).")
}
run()
// Prints "Holding ticket #7."
// Prints "Filing ticket #7 in the used-ticket bin."
```

<!--
  - test: `ownership-noncopyable-deinit`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int

         deinit {
             print("Filing ticket #\(claimNumber) in the used-ticket bin.")
         }
     }

  -> func run() {
         let ticket = CoatCheckTicket(claimNumber: 7)
         print("Holding ticket #\(ticket.claimNumber).")
     }
  -> run()
  <- Holding ticket #7.
  <- Filing ticket #7 in the used-ticket bin.
  ```
-->

The ticket's `deinit` runs as soon as `run()` returns,
because that's where `ticket`'s lifetime ends.

Sometimes a consuming method already does the work that `deinit` would do,
and running `deinit` afterward would repeat it.
For a case like that,
use `discard self` inside a `consuming` method
to end the value's lifetime without running its `deinit`:

```swift
struct CoatCheckTicket: ~Copyable {
    let claimNumber: Int

    deinit {
        print("Filing ticket #\(claimNumber) in the used-ticket bin.")
    }

    consuming func redeemed() -> Int {
        let number = claimNumber
        print("Filing ticket #\(number) in the used-ticket bin.")
        discard self
        return number
    }
}

func run() {
    let ticket = CoatCheckTicket(claimNumber: 42)
    let number = ticket.redeemed()
    print("Coat retrieved for ticket #\(number).")
}
run()
// Prints "Filing ticket #42 in the used-ticket bin."
// Prints "Coat retrieved for ticket #42."
```

<!--
  - test: `ownership-noncopyable-discard`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int

         deinit {
             print("Filing ticket #\(claimNumber) in the used-ticket bin.")
         }

         consuming func redeemed() -> Int {
             let number = claimNumber
             print("Filing ticket #\(number) in the used-ticket bin.")
             discard self
             return number
         }
     }

  -> func run() {
         let ticket = CoatCheckTicket(claimNumber: 42)
         let number = ticket.redeemed()
         print("Coat retrieved for ticket #\(number).")
     }
  -> run()
  <- Filing ticket #42 in the used-ticket bin.
  <- Coat retrieved for ticket #42.
  ```
-->

Because `redeemed()` already files the stub itself,
`discard self` tells Swift to skip the `deinit`
instead of filing the same stub a second time.
Discarding is deliberately narrow:
You can use it only within the module that declares the type,
and only when every stored property is trivial to dispose of on its own,
which keeps `discard self` from becoming a way to silently skip
cleanup that the compiler can't verify is safe to drop.

A noncopyable type comes with real restrictions, at least for now.
A `CoatCheckTicket` can't conform to most protocols yet
--- `Sendable` is the current exception ---
and it can't be stored in an `Array`,
passed as a type argument to most generic functions,
or wrapped in an `Optional`,
because those all assume their contents are copyable.
The next two sections show how Swift lifts exactly those restrictions,
for code that opts in to supporting noncopyable values.

## Noncopyable Types in Generic Code

Suppose the coat check counter also has a row of numbered lockers,
each one able to hold exactly one item.
Written generically,
a locker doesn't need to know what it's holding ---
it could be a `CoatCheckTicket`,
or it could be something else entirely:

```swift
struct Locker<Item> {
    var item: Item
}
```

<!--
  - test: `ownership-generics-err`

  ```swifttest
  -> struct Locker<Item> {
         var item: Item
     }
  ```
-->

Trying to put a `CoatCheckTicket` in a locker like this one doesn't work:

```swift
func run() {
    let locker = Locker(item: CoatCheckTicket(claimNumber: 1))
    print(locker.item.claimNumber)
}
run()
// Error: Generic struct 'Locker' requires that
// 'CoatCheckTicket' conform to 'Copyable'.
```

<!--
  - test: `ownership-generics-err`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> func run() {
         let locker = Locker(item: CoatCheckTicket(claimNumber: 1))
         print(locker.item.claimNumber)
     }
  -> run()
  !$ error: generic struct 'Locker' requires that 'CoatCheckTicket' conform to 'Copyable'
  !! let locker = Locker(item: CoatCheckTicket(claimNumber: 1))
  !!              ^
  ```
-->

The error happens because every generic parameter you write ---
`Item`, in this case ---
implicitly requires conformance to `Copyable`,
the same way it implicitly requires conformance to a few other
common protocols.
<doc:Generics#Implicit-Constraints> covers this in more detail,
including how to read and write the suppression syntax
that lifts an implicit constraint.
Applied to `Locker`,
suppressing the implicit `Copyable` constraint on `Item`
looks like this:

```swift
struct Locker<Item: ~Copyable>: ~Copyable {
    var item: Item
}
```

<!--
  - test: `ownership-generics`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> struct Locker<Item: ~Copyable>: ~Copyable {
         var item: Item
     }
  -> func run() {
         let locker = Locker(item: CoatCheckTicket(claimNumber: 1))
         print(locker.item.claimNumber)
     }
  -> run()
  <- 1
  ```
-->

Notice that `Locker` itself also has to suppress `Copyable`.
That's because a structure that stores a noncopyable value
can't offer a meaningful copy of itself either ---
copying the locker would require copying whatever item is inside it,
and there's no way to do that in general.
As with any noncopyable type,
suppressing `Copyable` on `Locker` is only the default;
if the type it's holding happens to be copyable,
you can restore `Locker`'s own copyability for just that case,
using a conditional conformance
of the kind you saw in <doc:Generics#Extensions-with-a-Generic-Where-Clause>:

```swift
extension Locker: Copyable where Item: Copyable {}
```

<!--
  - test: `ownership-generics-conditional`

  ```swifttest
  -> struct Locker<Item: ~Copyable>: ~Copyable {
         var item: Item
     }
  -> extension Locker: Copyable where Item: Copyable {}
  -> func run() {
         let numberLocker = Locker(item: 42)
         let anotherLocker = numberLocker
         print(numberLocker.item, anotherLocker.item)
     }
  -> run()
  <- 42 42
  ```
-->

Protocols suppress their inherited `Copyable` requirement
the same way types do,
which is what makes it possible for a noncopyable type
to conform to a protocol at all.
Recall from earlier that `CoatCheckTicket` couldn't conform to
ordinary protocols yet.
A protocol that's written to accept noncopyable conformers
lifts that restriction:

```swift
protocol Claimable: ~Copyable {
    consuming func redeemed() -> Int
}

extension CoatCheckTicket: Claimable {
    consuming func redeemed() -> Int {
        claimNumber
    }
}
```

<!--
  - test: `ownership-generics-protocol`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> protocol Claimable: ~Copyable {
         consuming func redeemed() -> Int
     }

  -> extension CoatCheckTicket: Claimable {
         consuming func redeemed() -> Int {
             claimNumber
         }
     }
  -> func run() {
         let ticket = CoatCheckTicket(claimNumber: 5)
         print(ticket.redeemed())
     }
  -> run()
  <- 5
  ```
-->

Without `~Copyable` in `Claimable`'s declaration,
every type conforming to it would implicitly need to be copyable,
which would rule out `CoatCheckTicket` before you even wrote
its `redeemed()` method.

## Noncopyable Values in Optionals

The coat check counter isn't always holding a ticket ---
sometimes nobody's there yet.
You can represent that with `Optional`,
the same way you would for any other type,
even though `CoatCheckTicket` is noncopyable:

```swift
var maybeTicket: CoatCheckTicket? = CoatCheckTicket(claimNumber: 9)
```

<!--
  - test: `ownership-optional`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> var maybeTicket: CoatCheckTicket? = CoatCheckTicket(claimNumber: 9)
  ```
-->

Optional binding and `nil` checks work the way you'd expect:

```swift
if let ticket = maybeTicket {
    print("Have ticket #\(ticket.claimNumber).")
}
maybeTicket = nil
print(maybeTicket == nil)
// Prints "Have ticket #9."
// Prints "true"
```

<!--
  - test: `ownership-optional`

  ```swifttest
  -> if let ticket = maybeTicket {
         print("Have ticket #\(ticket.claimNumber).")
     }
  <- Have ticket #9.
  -> maybeTicket = nil
  -> print(maybeTicket == nil)
  <- true
  ```
-->

There's one difference worth noticing.
For an ordinary, copyable optional,
`if let ticket = maybeTicket` copies the wrapped value out,
leaving `maybeTicket` untouched.
For a noncopyable optional, there's no implicit copy to make,
so unwrapping it this way *consumes* it,
the same as any other consuming use
of a noncopyable value:

```swift
var anotherMaybeTicket: CoatCheckTicket? = CoatCheckTicket(claimNumber: 3)
if let ticket = anotherMaybeTicket {
    print("Have ticket #\(ticket.claimNumber).")
}
print(anotherMaybeTicket == nil)
// Error: 'anotherMaybeTicket' used after consume.
```

<!--
  - test: `ownership-optional-err`

  ```swifttest
  -> struct CoatCheckTicket: ~Copyable {
         let claimNumber: Int
     }
  -> var anotherMaybeTicket: CoatCheckTicket? = CoatCheckTicket(claimNumber: 3)
  !$ error: 'anotherMaybeTicket' used after consume
  !! var anotherMaybeTicket: CoatCheckTicket? = CoatCheckTicket(claimNumber: 3)
  !! ^
  -> if let ticket = anotherMaybeTicket {
         print("Have ticket #\(ticket.claimNumber).")
     }
  !! ^ note: consumed here
  -> print(anotherMaybeTicket == nil)
  !! ^ note: used here
  ```
-->

After the `if let`, `anotherMaybeTicket` no longer has a value at all ---
not even `nil` --- so reading it again is an error,
the same as it would be for any other consumed value.
`switch` with `.some(_)` and `.none` patterns
follows the same rule, for the same reason.
If you need to look at a noncopyable optional's payload
without giving it up,
the standard library adds
a `ref` property for a borrowed look
and a `mutableRef` property for a mutable one,
so you don't have to restructure your code
around consuming the optional just to peek inside it.
As of Swift 6.4,
these additions are newer than the rest of this chapter's material,
so check the standard library's `Optional` documentation
for their exact availability.

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
-->
