# Codec System Design

## Overview

The Codec system provides `InvocationEncoder` and `InvocationDecoder` implementations that enable distributed method calls with `Codable` arguments over any transport.

## Problem Statement

When implementing a `DistributedActorSystem`, you must implement `remoteCall` and `remoteCallVoid` methods. These methods receive:
- A `RemoteCallTarget` identifying the method
- An `InvocationEncoder` to record arguments
- Return and error types

However, Swift's distributed actor system does not provide a concrete implementation of `InvocationEncoder`/`InvocationDecoder` - each transport must implement these protocols.

**The Problem**: Every transport implementation (BLE, gRPC, HTTP) ends up reimplementing the same logic:
1. Recording `Codable` arguments into `Data`
2. Extracting method identifiers from `RemoteCallTarget`
3. Decoding arguments on the server side
4. Encoding return values

This is **duplicate work** that should be shared across all transports.

## Solution

Provide a **transport-agnostic**, **Codable-based** implementation of `InvocationEncoder` and `InvocationDecoder` in the runtime library.

### Key Constraints

1. **Codable-only**: All arguments, return values, and errors must conform to `Codable`
2. **Mangled names**: Use Swift's mangled function names as method identifiers
3. **Type erasure**: Store everything as `Data` internally for transport independence

## Architecture

```
┌─────────────────────────────────────────────┐
│   Swift Compiler (distributed func)         │
│   - Generates RemoteCallTarget               │
│   - Contains mangled name                    │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│   DistributedActorSystem.remoteCall         │
│   - Receives RemoteCallTarget                │
│   - Receives InvocationEncoder               │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│   CodableInvocationEncoder (this library)   │
│   - Records Codable arguments → Data         │
│   - Extracts identifier from target          │
│   - Bundles into InvocationEnvelope          │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│   Transport (BLE, gRPC, HTTP)               │
│   - Serializes InvocationEnvelope            │
│   - Sends over wire                          │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│   Server: CodableInvocationDecoder          │
│   - Decodes arguments from Data              │
│   - Provides to executeDistributedTarget     │
└──────────────────────────────────────────────┘
```

## Design Decisions

### 1. Codable-Based Storage

**Decision**: Store all arguments as `[Data]` (array of encoded values)

**Rationale**:
- Each argument encoded independently
- Preserves argument boundaries
- Allows sequential decoding
- Type information preserved through generic constraints

**Alternative Considered**: Single `Data` blob with custom framing
- ❌ More complex
- ❌ Requires custom framing protocol
- ❌ Error-prone

### 2. Method Identification

**Decision**: Use `target.identifier` to get the mangled name

**Rationale**:
- Swift's `RemoteCallTarget` has a public `identifier` property containing the mangled name
- Direct property access is simpler and more reliable than string parsing
- Stable across Swift versions (part of the distributed actors API)

**Format Example**:
```swift
let target: RemoteCallTarget = // ... from Swift runtime
let identifier = target.identifier
// identifier = "$s10MyModule9MySensor15readTemperatureySdYaKF"
```

### 3. Encoder State Machine

**States**:
1. `recording` - Accumulating arguments
2. `finished` - Ready to create envelope
3. `consumed` - Envelope created, encoder no longer usable

**Rationale**: Prevents misuse (e.g., recording after encoding)

### 4. Error Handling

**Codable Errors Only**: Transport-level errors use `RuntimeError`, but user errors must be `Codable & Error`

**Rationale**:
- Allows error propagation across network
- Maintains type safety
- Transport-agnostic

## Protocol Definitions

### InvocationEncoder

```swift
/// Records arguments and metadata for a distributed method call.
///
/// Usage:
/// ```swift
/// func remoteCall<Act, Err, Res>(
///     on actor: Act,
///     target: RemoteCallTarget,
///     invocation: inout InvocationEncoder,
///     throwing: Err.Type,
///     returning: Res.Type
/// ) async throws -> Res {
///     var encoder = invocation as! CodableInvocationEncoder
///     encoder.recordTarget(target)
///     let envelope = try encoder.makeInvocationEnvelope(
///         recipientID: actor.id,
///         senderID: nil
///     )
///     // Send envelope over transport...
/// }
/// ```
public protocol InvocationEncoder {
    /// Record a generic type substitution.
    mutating func recordGenericSubstitution<T>(_ type: T.Type) throws

    /// Record an argument value.
    mutating func recordArgument<Value: Codable>(_ argument: Value) throws

    /// Record the expected return type.
    mutating func recordReturnType<R: Codable>(_ type: R.Type) throws

    /// Record the expected error type.
    mutating func recordErrorType<E: Error>(_ type: E.Type) throws

    /// Mark recording as complete.
    mutating func doneRecording() throws
}
```

### InvocationDecoder

```swift
/// Decodes arguments and metadata from a received invocation.
///
/// Usage:
/// ```swift
/// let envelope = // ... received from transport
/// var decoder = CodableInvocationDecoder(envelope: envelope)
///
/// try await executeDistributedTarget(
///     on: actor,
///     target: target,
///     invocationDecoder: &decoder,
///     handler: resultHandler
/// )
/// ```
public protocol InvocationDecoder {
    /// Decode generic type substitutions.
    mutating func decodeGenericSubstitutions() throws -> [Any.Type]

    /// Decode the next argument in sequence.
    mutating func decodeNextArgument<Argument: Codable>() throws -> Argument

    /// Decode the return type.
    mutating func decodeReturnType() throws -> Any.Type?

    /// Decode the error type.
    mutating func decodeErrorType() throws -> Any.Type?
}
```

## Implementation: CodableInvocationEncoder

### Internal State

```swift
public struct CodableInvocationEncoder: InvocationEncoder {
    private enum State {
        case recording
        case finished
        case consumed
    }

    private var state: State = .recording
    private var arguments: [Data] = []
    private var target: RemoteCallTarget?
    private var genericSubstitutions: [String] = []
    private var returnTypeInfo: String?
    private var errorTypeInfo: String?

    // ... implementation
}
```

### Key Methods

#### Recording Arguments

```swift
public mutating func recordArgument<Value: Codable>(_ argument: Value) throws {
    guard state == .recording else {
        throw RuntimeError.invalidState("Cannot record after encoding")
    }

    let data = try JSONEncoder().encode(argument)
    arguments.append(data)
}
```

#### Recording Generic Substitutions

```swift
public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
    guard state == .recording else {
        throw RuntimeError.invalidState("Cannot record generic substitution after encoding")
    }
    // Store the runtime-mangled type name so it can be resolved back via
    // _typeByName on the receiving side. String(reflecting:) is NOT usable here:
    // it yields a human-readable name that _typeByName cannot resolve for
    // generic/optional/collection/user-defined types.
    genericSubstitutions.append(_mangledTypeName(type) ?? _typeName(type))
}
```

#### Creating Envelope

```swift
public mutating func makeInvocationEnvelope(
    recipientID: String,
    senderID: String? = nil
) throws -> InvocationEnvelope {
    guard state == .finished else {
        throw RuntimeError.invalidState("Must call doneRecording() first")
    }

    guard let target = target else {
        throw RuntimeError.invalidState("Target not recorded")
    }

    // Arguments are already individually encoded; pass the list through directly
    // so the bytes are not re-encoded when the envelope is later serialized.
    let envelope = InvocationEnvelope(
        recipientID: recipientID,
        senderID: senderID,
        target: extractIdentifier(from: target),
        genericSubstitutions: genericSubstitutions,  // Include generic type info
        arguments: arguments,
        metadata: .init()
    )

    state = .consumed
    return envelope
}

private func extractIdentifier(from target: RemoteCallTarget) -> String {
    // Use the identifier property directly - it contains the mangled name
    return target.identifier
}
```

#### Accessing Encoded Arguments

For advanced use cases where custom transport implementations need to inspect argument data before creating the envelope:

```swift
public func encodedArguments() throws -> [Data] {
    guard state == .finished else {
        throw RuntimeError.invalidState("Must call doneRecording() before accessing arguments")
    }
    return arguments
}
```

**Use Case Example**:
```swift
// In a custom transport that needs to inspect arguments
var encoder = invocation as! CodableInvocationEncoder
encoder.recordTarget(target)

// Access encoded arguments to check size or content
let arguments = try encoder.encodedArguments()
if arguments.contains(where: { $0.count > maxBLEPacketSize }) {
    // Handle large arguments differently
}

// Then create envelope as usual
let envelope = try encoder.makeInvocationEnvelope(recipientID: actor.id)
```

## Implementation: CodableInvocationDecoder

### Internal State

```swift
public struct CodableInvocationDecoder: InvocationDecoder {
    private var arguments: [Data]
    private var genericSubstitutions: [String]
    private var currentIndex: Int = 0

    public init(envelope: InvocationEnvelope) throws {
        // Arguments are already a list of individually encoded blobs.
        self.arguments = envelope.arguments
        self.genericSubstitutions = envelope.genericSubstitutions
    }

    // ... implementation
}
```

### Key Methods

#### Decoding Generic Substitutions

```swift
public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
    // Convert mangled type names back to Type objects using Swift's internal _typeByName
    return try genericSubstitutions.compactMap { mangledName in
        guard let type = _typeByName(mangledName) else {
            throw RuntimeError.serializationFailed(
                "Failed to resolve generic type from mangled name: \(mangledName)"
            )
        }
        return type
    }
}
```

**Note**: This uses Swift's internal `_typeByName()` function to resolve mangled type names. This is the same approach used by Apple's swift-distributed-actors.

#### Decoding Arguments

```swift
public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
    guard currentIndex < arguments.count else {
        throw RuntimeError.serializationFailed("No more arguments to decode")
    }

    let data = arguments[currentIndex]
    currentIndex += 1

    return try JSONDecoder().decode(Argument.self, from: data)
}
```

## Usage Example

### Client Side (remoteCall)

```swift
public func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing: Err.Type,
    returning: Res.Type
) async throws -> Res where Act: DistributedActor {
    // Cast to our concrete implementation
    var encoder = invocation as! CodableInvocationEncoder

    // Record the target
    encoder.recordTarget(target)

    // Create envelope (arguments already recorded by Swift runtime)
    let envelope = try encoder.makeInvocationEnvelope(
        recipientID: actor.id.description,
        senderID: nil
    )

    // Send via transport
    let response = try await transport.sendInvocation(envelope)

    // Decode result
    switch response.result {
    case .success(let data):
        return try JSONDecoder().decode(Res.self, from: data)
    case .void:
        return () as! Res
    case .failure(let error):
        throw error
    }
}
```

### Server Side (handling invocation)

```swift
// Receive envelope from transport
for await envelope in transport.incomingInvocations {
    // Find actor
    guard let actor = registry.find(id: envelope.recipientID) else {
        // Send error response
        continue
    }

    // Create decoder
    var decoder = try CodableInvocationDecoder(envelope: envelope)

    // Reconstruct RemoteCallTarget
    let target = try RemoteCallTarget(identifier: envelope.target)

    // Create result handler
    let handler = CodableResultHandler { result in
        let responseEnvelope: ResponseEnvelope
        switch result {
        case .success(let value):
            let data = try JSONEncoder().encode(value)
            responseEnvelope = ResponseEnvelope(
                callID: envelope.callID,
                result: .success(data)
            )
        case .void:
            responseEnvelope = ResponseEnvelope(
                callID: envelope.callID,
                result: .void
            )
        case .failure(let error):
            responseEnvelope = ResponseEnvelope(
                callID: envelope.callID,
                result: .failure(RuntimeError.executionFailed(error))
            )
        }

        try await transport.sendResponse(responseEnvelope)
    }

    // Execute via Swift runtime
    try await executeDistributedTarget(
        on: actor,
        target: target,
        invocationDecoder: &decoder,
        handler: handler
    )
}
```

## Testing Strategy

### Unit Tests

1. **Encoder Tests**:
   - Record single argument
   - Record multiple arguments
   - Record different Codable types
   - State machine transitions
   - Error cases (double encoding, etc.)

2. **Decoder Tests**:
   - Decode single argument
   - Decode multiple arguments in sequence
   - Type mismatches
   - Insufficient arguments

3. **Round-trip Tests**:
   - Encode → Decode → Compare
   - Complex nested structures
   - Optional values
   - Arrays and dictionaries

### Integration Tests

1. **Mock Transport**:
   - Full client → server → client round trip
   - Actual distributed actor methods
   - Error propagation
   - Concurrent calls

## Performance Considerations

### Encoding Overhead

Per method call:
- N × `JSONEncoder().encode()` calls (N = number of arguments)
- 1 × array encoding (wrapping individual arguments)
- ~100-500μs for typical methods (1-5 arguments)

**Compared to**:
- Network latency: 10-100ms (BLE, HTTP)
- The encoding overhead is **negligible** (< 1%)

### Memory Usage

Per call:
- Temporary `Data` objects for each argument
- Released immediately after envelope creation
- No persistent memory overhead

### Optimization Opportunities

1. **Reusable Encoders**: Pool JSONEncoder instances
2. **Binary Format**: Replace JSON with MessagePack or Protobuf
3. **Streaming**: For large arguments, stream instead of buffering

## Generic Method Support

The Codec system fully supports distributed methods with generic type parameters:

### Generic Methods

```swift
distributed actor DataStore {
    typealias ActorSystem = InMemoryActorSystem

    distributed func store<T: Codable>(_ value: T, key: String) { ... }
    distributed func fetch<T: Codable>(key: String) -> T? { ... }
}
```

### Generic Actors

```swift
distributed actor GenericContainer<T: Codable & Sendable> {
    typealias ActorSystem = InMemoryActorSystem

    private var value: T

    distributed func getValue() -> T { return value }
    distributed func setValue(_ newValue: T) { value = newValue }
}

// Usage
let container = GenericContainer(initialValue: 42, actorSystem: system)
let value = try await container.getValue() // Type-safe: returns Int
```

### How It Works

1. **Encoder** records generic type substitutions using `recordGenericSubstitution<T>(_:)`
2. **InvocationEnvelope** transmits mangled type names as `[String]`
3. **Decoder** resolves type names back to `Any.Type` using `_typeByName()`
4. **Swift Runtime** uses resolved types to correctly dispatch generic methods

### Limitations

- **Codable Constraint**: All generic parameters must conform to `Codable` (and `Sendable` for actor type parameters)
- **No Closures**: Closures cannot be distributed method parameters because they don't conform to `Codable`

## Future Enhancements

### Phase 1 (v0.2.0): Core Codec
- ✅ CodableInvocationEncoder
- ✅ CodableInvocationDecoder
- ✅ RemoteCallTarget helpers
- ✅ Generic method support
- ✅ Generic actor support

### Phase 2 (v0.3.0): Advanced Features
- Binary codec (MessagePack)
- Streaming arguments
- Compression support

### Phase 3 (v0.4.0): Optimization
- Encoder pooling
- Zero-copy for large Data
- Custom type optimizations

## References

- [Swift Distributed Actors (SE-0336)](https://github.com/apple/swift-evolution/blob/main/proposals/0336-distributed-actor-isolation.md)
- [Swift Distributed Actor Runtime Proposal (SE-0344)](https://github.com/apple/swift-evolution/blob/main/proposals/0344-distributed-actor-runtime.md)
- Swift Standard Library: `Codable`, `JSONEncoder`, `JSONDecoder`
