# Ownership

Control the ability to copy and store types.

By default, types you write in Swift gain certain capabilities without you
having to write any code. 
Variables of these types can be copied into other local or global variables, 
and into stored properties of another type. 
They can also be passed to any function that accepts that type. 
This is made possible because Swift generates the code to handle the copying 
of a type, and inserts calls to this copying code automatically if needed. 
For classes, this involves incrementing the reference count of the object. 
For structures, it involves copying the individual stored properties into a 
new instance. 
For enumerations, the associated values of the case are copied.

> **Note**
> Swift does not allow you to customize the way a value is copied, 
> or detect when a value is being copied. 
> The only way to determine if a reference to a class instance has been copied 
> is afterwards, using the `isKnownUniquelyReferenced` function, which
> returns `true` if there is more than one variable referencing the class. 
> Value types that hold a class reference in a stored property can use this 
> to detect that they have been copied. This is how types like `Array` 
> and `String` implement their copy-on-write behavior.

This default assumption of copyability is the right choice for most use cases.
However, in some cases it is important to constrain the ability to make 
copies of an instance. 
Often this is because the type controls a resource, 
such as a file handle or memory allocation, 
and allowing copies would interfere with goals such as correctness 
or runtime performance.

## Suppressing Copyability

You can suppress Swift's default assumption that a type is copyable
using the `~Copyable` constraint:

```swift
struct File: ~Copyable {
    private let handle: Int32
    
    init(named name: String) {
        // Open file using sytem API,
        // storing the file handle.
    }
    var size: Int {
        // Retrieve size of file from
        // file system using handle.
    }
}
```

The inclusion of the `~Copyable` constraint on the structure definition stops 
the compiler from automatically adding the ability to copy the `File` type. 
This constraint must appear on the declaration of the type, it cannot be
added in an extension.

Since the type does not support copying, Swift prevents you from 
performing operations that would require copying:

```swift
let originalFileVariable = File(named: "swift.txt")
print(originalFile.handle)

let secondFileVariable = originalFile
print(originalFile.size)
// This is a compile-time error: originalFileVariable cannot
// be used after its value is assigned to secondFileVariable.
```

Assigning the file instance to a new variable does not involve making a copy
of the value, because `File` does not support copying. 
This assignment is referred to as "consuming" the original value. 
You cannot use a variable after its value is consumed.
In reporting the error, 
the Swift compiler will show the location where the value was consumed, 
and where it is subsequently used.

In some cases, it is not permitted to consume a value. Global variables 
cannot be consumed, as it would not be possible to prevent them 
from subsequent use in other functions:

```swift
var globalFileVariable = File(named: "swift.txt")

func process() {
  let localFileVariable = globalFile
  // This is a compile-time error: global variables cannot be consumed.
}
```

The `Optional` type has the ability to take a noncopyable value, 
leaving a `nil` behind, 
which you can use if a global variable needs to be consumable:

```swift
var globalFileVariable: File? = File(named: "swift.txt")

func process() {
    if let localFile = globalFile.take() {
        // Use localFile, which now owns the File
        // instance previosuly held in the global
        // variable, which now holds nil.
    } else {
        // handle nil value for the file
    }
}
```

When working with enumerations (including `Optional`), associated values 
can be extracted temporarily into a variable using Swift's pattern matching:

```swift
func process() {
    switch globalFileVariable {
    case let localFile?:
        // Use localFile, the wrapped value temporarily
        // borrowed from the global optional variable.
    case nil:
        // handle nil value for the global file variable
    }
}
```

## Deinitialzers on Value Types

As described in <doc:Deinitialization>, class types can be given code that 
runs when the class is destroyed. 
Copyable structures and enumerations cannot have a deinitializer. 
When these types are noncopyable, they can, 
because they have unique ownership of their data:

```swift
struct File: ~Copyable {
    let handle: Int32
    
    init(from name: String) {
        // open file and store file handle
    }
    
    deinit {
        // Since file handle cannot be shared
        // with any other instance, it can
        // be closed here.
    }
}
```

This allows a noncopyable structure to be used to manage resources, 
in a similar manner to classes. 
There are pros and cons to using a noncopyable type in this way. 
Unlike classes, noncopyable types are uniquely owned and do not need 
reference counting and heap allocation, reducing runtime overhead. 
They also cannot be shared, making it easier to ensure they are safely 
`Sendable` and reducing the overhead needed for Swift to ensure
<doc:MemorySafety>. This comes at the cost that working with noncopyable 
values is less convenient, as seen with the global variable example above.

## Types Holding Noncopyable Values

If a type holds another noncopyable type as a stored property, that type
also cannot be copyable, since there would be no way to perform a full
copy of each of the type's stored properties:

```swift
struct Package {
    var manifest: File
    // This is a compile-time error: Package is Copyable
}
```

The containing type must also be marked as noncopyable:

```swift
struct Package: ~Copyable {
    var manifest: File
}
```

Since class instances are not copied – only references to them – a class type
can hold noncopyable types.

As `Array` and `Dictionary` are copyable types, they cannot hold noncopyable
elements. `InlineArray` however is only conditionally copyable, as described
below, so can hold noncopyable elements.

## Specifying Ownership in Functions

Functions that operate on noncopyable types require additional information
on their parameters, specifying whether the function is _borrowing_ or 
_consuming_ the value, or taking it `inout`.

This is done with an additional modifier, in the same position as the
`inout` qualifier. Unlike copyable types, noncopyable types _must_ specify
one of the three options here.

If the function is only borrowing
the value, and will not be keeping it, then the `borrowing` keyword is used:

```swift
func printSize(of file: borrowing File) {
    print("The file is \(file.size) bytes")
}
```

If the function needs to keep the value, it must use the `consuming` keyword. 
The most common case is with initializers:

```swift
init(manifest: consuming File) {
    self.manifest = manifest
}
```

If a function borrows a parameter, it cannot then consume it in its implementation:

```swift
init(manifest: borrowing File) {
    self.manifest = manifest
    // This is a compile-time error: manifest is borrowed and cannot be consumed.
}
```

If a function consumes an argument, that means it can no longer be used after
being passed in:

```swift
let package = Package(manifest: file)
print(file.size)
// This is a compile-time error: file cannot be used after it is consumed.
```

> **Note**
> With copyable types, Swift follows the convention of borrowing arguments
> passed to functions, except for initializers that consume their arguments.
> This is optimal for minimizing reference counting. The `borrowing` and
> `consuming` keywords can also be used with copyable types to change these 
> defaults. For example, the `append` method on `Array` is annotated as 
> consuming the element to be appended.

Methods on noncopyable types can also be marked as `consuming` if they 
must represent the final use of a type:

```swift
extension File {
    // Explicitly close the file, rather than allowing the deinit to do it.
    // The file should not be used after it is closed.
    consuming func close() {
        discard self
        // call the system API to close a file handle
    }
}
```

Here, the `discard` keyword has been used to indicate that the `deinit` for
this type should not run. In the case of `File`, this is necessary to avoid
the file handle being closed twice.

## Generics and Copyability

In order to conform a noncopyable type to a protocol, that protocol cannot
assume the conforming type is copyable. Like with types, this is expressed 
with the `~Copyable` constraint:

```swift
protocol SizeProviding: ~Copyable {
   var size: Int { get }
}
```

This annotation states that a conformance to `SizeProvididing` cannot
mean the conforming value will be copyable. Without this, a copyable type could
not conform, because extensions on the protocol might make copies of `Self`
in their implementations – something they are free to do in extensions
to copyable protocols.

> **Note**
> Until now, we have seen `~Copyable` applied to type declarations to
> make them noncopyable. Adding a `~Copyable` constraint to a protocol
> is not as strict. It means conforming types do not _have_ to be 
> copyable. But this does not prevent copyable types from conforming to
> the protocol. For this reason, whenever you see it, `~Copyable` should be
> viewed as meaning "don't assume a type is copyable" rather than
> "a type is not copyable".

Since `SizeProviding` does not require its conforming types to be copyable,
the `File` type can conform to it:

```swift
extension File: SizeProviding { }
// requirements are fulfilled by File's existing API
```

If `SizeProviding` had not included the `~Copyable` constraint, this
conformance would have generated a compile-time error that `File' does not
conform to protocol 'Copyable'.


Just like with protocols, generic placeholders can be annotated with the
`~Copyable` constraint, allowing both noncopyable types to be used for the 
generic type. An example of this is the declaration of the `Optional` type:

```
enum Optional<Wrapped: ~Copyable>: ~Copyable {
  case some(Wrapped)
  case none
}
```

The `Optional` type can therefore wrap both noncopyable types (such as the 
`File` type above) and copyable types.

Just as a type that wraps a noncopyable stored property must itself be 
noncopyable, the `Optional` enum must be noncopyable in order to be able
to hold a _potentially_ noncopyable value. "Potentially" noncopyable because,
just like with the protocol constraint, `~Copyable` here only means "don't
assume this value is copyable".

## Extensions and Copyability

Marking a protocol as `~Copyable` makes it more flexible: it can be conformed
to by both copyable and noncopyable types. A protocol might be marked
`~Copyable` even though nearly every type conforming to it is actually 
copyable. 

The same goes for generic types. Allowing a type to work with both copyable
and noncopyable types makes it more useful. This is why Swift's `Optional'
type is written to work this way.

In Swift, most code is written assuming copyability. This default assumption
extends to protocol extensions and extensions on generic types. By default,
Swift assumes copyability of all the types involved in your extension.

Here is an extension on `Optional` that either unwraps the value, 
or throws an error if the optional is nil:

```swift
extension Optional {
    struct UnwrapFailure: Error { }
    
    func unwrapOrThrow() throws -> Wrapped {
        guard let value = self else { throw UnwrapFailure() }
        return value
    }
}
```

This code assumes that the value wrapped by the optional is copyable. If it
was not, then it cannot just be unwrapped and returned because it would
now be in two places: still inside the optional, and returned to the caller.
This would require making a copy.

This code does compile without errors, because Swift assumes that extensions
by default only apply to copyable elements.

To change this code to apply to noncopyable elements too, you would need
to explicitly state this in the extension, and also mark the function
as consuming.

```swift
extension Optional where Wrapped: ~Copyable {
    consuming func unwrapOrThrow() throws -> Wrapped {
        guard let value = self else { throw UnwrapFailure() }
        return value
    }
}
```

Since the function is marked consuming, the optional value
would no longer be available, allowing the unwrapped value to be returned
without needing to copy it.

> Many Swift programmers use types like `Optional` that work with noncopyable
> values, without even being aware of features like ownership. The default
> assumption of copyability helps keep the learning curve shallow, and ensures 
> that you can mark your types and protocols as supporting noncopyable types 
> without making them harder to use for anyone who doesn't want to deal
> with more advanced language features.

## Conditional Copyability

Sometimes whether a generic type is copyable depends on one of its 
placeholders. We have already seen an example of this, with the `Optional` 
type. An `Optional` type that wraps a copyable type can be copied, whereas
one that wraps a noncopyable type cannot.

To conditionalize copyability on a placeholder, you can write a conditional
conformance to the `Copyable` protocol, with a where clause that depends on
another type being copyable:

```swift
extension Optional: Copyable where Wrapped: Copyable { }
```

The `Copyable` conformance does not need to fulfill any protocol requirements –
these are handled by the Swift compiler.

This conformance can only be added in the module in which the type is defined.

Types that have a deinitializer cannot be made conditionally copyable.
