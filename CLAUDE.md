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
swift test --filter MethodRegistryTests
```

### Clean build artifacts
```bash
swift package clean
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
   - `InvocationEnvelope`: Represents a method call (callID, recipientID, target method, arguments)
   - `ResponseEnvelope`: Represents the result (callID, result/error)
   - `InvocationResult`: Enum for success/void/failure
   - These are transport-agnostic; transports serialize them to their native format

2. **Registry System**
   - `ActorRegistry` (`Sources/ActorRuntime/Core/ActorRegistry.swift`): Maps actor IDs to instances
   - `MethodRegistry` (`Sources/ActorRuntime/Core/MethodRegistry.swift`): Maps method names to executable closures
   - Both use `Synchronization.Mutex` for thread-safe access (not `@unchecked Sendable` or `NSLock`)

3. **Error System** (`Sources/ActorRuntime/Core/RuntimeError.swift`)
   - `RuntimeError`: Codable error types for distributed errors
   - Cases: actorNotFound, methodNotFound, executionFailed, serializationFailed, timeout, etc.

4. **Transport Protocol** (`Sources/ActorRuntime/Transport/TransportProtocol.swift`)
   - `DistributedTransport`: Interface all transport implementations must conform to
   - Methods: `sendInvocation()`, `incomingInvocations`, `sendResponse()`, `close()`

5. **Serialization System** (`Sources/ActorRuntime/Serialization/SerializationSystem.swift`)
   - `SerializationSystem`: Protocol for pluggable serialization
   - `JSONSerializationSystem`: Default JSON implementation
   - Transports can provide custom implementations (Protobuf, MessagePack, etc.)

### Key Design Decisions

- **No Reflection**: Swift doesn't expose APIs to execute distributed methods by name, so `MethodRegistry` provides manual registration
- **Type Erasure**: Methods registered as `(Data) async throws -> Data`; type safety via `Codable` at boundaries
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
6. Runtime finds method via `MethodRegistry.execute(_:arguments:)`
7. Runtime executes method and captures result
8. Runtime creates `ResponseEnvelope` with result

### Server → Client (Response):
9. Transport serializes `ResponseEnvelope`
10. Transport sends over wire
11. Client transport deserializes
12. Transport matches callID to pending call
13. Transport resumes continuation with result

## Thread Safety Model

- `ActorRegistry` and `MethodRegistry` are `final class` with `Mutex<State>`
- Not `actor` types because `DistributedActorSystem` requires synchronous access
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

## Testing Strategy

- Unit tests verify individual components (envelopes, registries, errors)
- Integration tests use real `DistributedActor` instances with a mock `ActorSystem`
- Tests check thread safety via concurrent access patterns
- Mock transports used for integration testing without real network
- All tests in `Tests/ActorRuntimeTests/`
