# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`swift-actor-runtime` provides transport-agnostic primitives for implementing Swift Distributed Actor systems. It extracts common patterns (envelopes, registries, errors) into a shared runtime library so transport implementations (BLE, gRPC, HTTP) can focus on connectivity rather than reinventing RPC infrastructure.

**Core Philosophy**: "Write once, run on any transport"

## Build Commands

### Build the package
```bash
swift build
```

### Run all tests
```bash
swift test
```

### Run a specific test
```bash
swift test --filter <TestName>
```

For example:
```bash
swift test --filter ActorRegistrySimpleTests
swift test --filter ActorRegistryIntegrationTests
```

### Clean build artifacts
```bash
swift package clean
```

## Release Process

### Version Tagging

**IMPORTANT**: This project uses version tags **WITHOUT** the `v` prefix.

- ✅ Correct: `0.1.0`, `0.2.0`, `1.0.0`
- ❌ Incorrect: `v0.1.0`, `v0.2.0`, `v1.0.0`

### Creating a Release

```bash
# Create an annotated tag
git tag -a 0.1.0 -m "Release 0.1.0"

# Push to remote
git push origin 0.1.0

# To delete a tag if needed
git tag -d 0.1.0
git push origin :refs/tags/0.1.0
```

## Architecture Overview

The runtime sits between user-defined distributed actors and transport implementations:

```
User Distributed Actors
         ↓
Transport Implementation (Bleu, ActorEdge, etc.)
         ↓
swift-actor-runtime (this library)
```

### Core Components and Their Relationships

1. **Envelope System** (`Sources/ActorRuntime/Core/Envelope.swift`)
   - `InvocationEnvelope`: Represents a method call (callID, recipientID, target method, genericSubstitutions, arguments)
   - `ResponseEnvelope`: Represents the result (callID, result/error)
   - `InvocationResult`: Enum for success/void/failure
   - These are transport-agnostic; transports serialize them to their native format
   - `genericSubstitutions: [String]` field stores mangled type names for generic methods

2. **Registry System**
   - `ActorRegistry` (`Sources/ActorRuntime/Core/ActorRegistry.swift`): Maps actor IDs to instances
   - Uses `Synchronization.Mutex` for thread-safe access (not `@unchecked Sendable` or `NSLock`)

3. **Codec System** (`Sources/ActorRuntime/Codec/`)
   - `CodableInvocationEncoder`: Records distributed method arguments as Codable Data
   - `CodableInvocationDecoder`: Decodes arguments from InvocationEnvelope
   - `CodableResultHandler`: Encodes return values into ResponseEnvelope
   - Enables transport-agnostic method calls with type-safe Codable arguments
   - **Generic Support**: Full support for generic methods and generic actors via type substitution

4. **Error System** (`Sources/ActorRuntime/Core/RuntimeError.swift`)
   - `RuntimeError`: Codable error types for distributed errors
   - Cases: actorNotFound, methodNotFound, executionFailed, serializationFailed, timeout, etc.

5. **Transport Protocol** (`Sources/ActorRuntime/Transport/TransportProtocol.swift`)
   - `DistributedTransport`: Interface all transport implementations must conform to
   - Methods: `sendInvocation()`, `incomingInvocations`, `sendResponse()`, `close()`
   - All envelopes are `Codable` and can be serialized using standard Swift encoders/decoders

### Key Design Decisions

- **Use executeDistributedTarget**: Swift provides `executeDistributedTarget` for method dispatch - no manual registration needed
- **Thread Safety via Mutex**: All registries use `Synchronization.Mutex` (Swift 6.0+) for Sendable conformance without `@unchecked`
- **String IDs not UUIDs**: Actor/call identifiers are strings to allow custom ID schemes
- **Zero Dependencies**: Pure Swift standard library for maximum compatibility

## RPC Data Flow

### Client → Server (Method Call):
1. Client calls `actor.method()`
2. Transport creates `InvocationEnvelope` with callID, recipientID, target, arguments
3. Transport serializes and sends over wire
4. Server transport deserializes to `InvocationEnvelope`
5. Runtime finds actor via `ActorRegistry.find(id:)`
6. **Swift runtime executes method via `executeDistributedTarget`** (automatic dispatch)
7. Method executes and returns result
8. Runtime creates `ResponseEnvelope` with result

### Server → Client (Response):
9. Transport serializes `ResponseEnvelope`
10. Transport sends over wire
11. Client transport deserializes
12. Transport matches callID to pending call
13. Transport resumes continuation with result

### Key Point: executeDistributedTarget
The Swift runtime's `executeDistributedTarget` handles:
- Looking up the distributed function from `RemoteCallTarget`
- Decoding arguments from `InvocationDecoder`
- Dispatching to the actual method implementation
- Handling results via `ResultHandler`

**No manual method registration needed!**

## Thread Safety Model

- `ActorRegistry` is a `final class` with `Mutex<State>`
- Not an `actor` type because `DistributedActorSystem` requires synchronous access
- Lock granularity is per-registry instance to minimize contention
- All public APIs are thread-safe and can be called from any context

## Platform Requirements

- Swift 6.2+ (for `Synchronization.Mutex`)
- iOS 18.0+, macOS 15.0+, watchOS 11.0+, tvOS 18.0+, visionOS 2.0+

## Known Transport Implementations

- [Bleu](https://github.com/1amageek/Bleu) - Bluetooth Low Energy (BLE)
- [ActorEdge](https://github.com/1amageek/actor-edge) - gRPC

## Memory Management

### ActorRegistry Lifecycle

**Important**: `ActorRegistry` holds **strong references** to registered actors.

- You **must** call `unregister(id:)` when actors are no longer needed
- Failure to unregister can cause memory leaks in long-running systems
- Consider implementing cleanup logic in your transport's `close()` method

Example cleanup pattern:
```swift
// In your ActorSystem implementation
func close() async throws {
    // Unregister all actors before shutdown
    registry.clear()

    // Or unregister individually
    for id in registry.allActorIDs() {
        registry.unregister(id: id)
    }
}
```

**Why strong references?**
- Predictable lifecycle management
- User has explicit control over actor deallocation
- Simpler than weak references which can lead to unexpected deallocations

### Recursive Lock Prevention

The `ActorRegistry` implementation carefully avoids recursive locks when actors are deallocated:
- `unregister(id:)` and `clear()` extract actors from the dictionary while holding the lock
- Actors are released **outside** the lock scope
- This prevents deadlocks if actor `deinit` calls `resignID()` (which acquires the same lock)

## Generic Method Support

The runtime fully supports distributed methods with generic type parameters and generic distributed actors.

### Implementation Details

1. **Type Recording**: `CodableInvocationEncoder.recordGenericSubstitution<T>(_:)` records mangled type names
2. **Type Transmission**: `InvocationEnvelope.genericSubstitutions: [String]` carries type information
3. **Type Resolution**: `CodableInvocationDecoder.decodeGenericSubstitutions()` uses `_typeByName()` to resolve types
4. **Type Safety**: Swift's runtime ensures correct generic method dispatch

### Examples

**Generic Methods**:
```swift
distributed actor DataStore {
    distributed func store<T: Codable>(_ value: T, key: String) { }
    distributed func fetch<T: Codable>(key: String) -> T? { }
}
```

**Generic Actors**:
```swift
distributed actor GenericContainer<T: Codable & Sendable> {
    distributed func getValue() -> T { }
    distributed func setValue(_ newValue: T) { }
}
```

### Constraints

- All generic type parameters must conform to `Codable`
- For actor type parameters, types must also conform to `Sendable`
- Closures cannot be distributed method parameters (not `Codable`)

## Testing Strategy

- Unit tests verify individual components (envelopes, registries, errors)
- Integration tests use real `DistributedActor` instances with a mock `ActorSystem`
- Generic actor tests verify type-safe distributed calls with Int, String, and custom structs
- Tests check thread safety via concurrent access patterns
- Mock transports used for integration testing without real network
- All tests in `Tests/ActorRuntimeTests/` (55 tests including generic support)
