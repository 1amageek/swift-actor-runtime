# Swift Actor Runtime - Design Document

## Problem Statement

Swift's Distributed Actor system provides excellent abstractions for writing distributed code, but:

1. **Transport coupling**: Each implementation re-invents envelopes, registries, errors
2. **Code duplication**: Common patterns repeated across projects
3. **Ecosystem fragmentation**: Hard to switch transports or mix them
4. **Lack of shared primitives**: No standard types for transport-agnostic RPC

## Solution

Extract transport-agnostic primitives into a shared runtime library that:
- Provides standard envelopes for RPC
- Manages actor instance registries
- Defines common error types
- Establishes transport protocol interface
- Leverages Swift's built-in `executeDistributedTarget` for method dispatch

## Understanding Swift's Distributed Actor System

### How `executeDistributedTarget` Works

Swift's distributed actor system provides `executeDistributedTarget` as part of the `DistributedActorSystem` protocol. This method is **not** a required implementation - it has a default implementation provided by the Swift runtime.

**Key Point**: You do **not** need to manually register methods. The Swift compiler and runtime handle method dispatch automatically.

### Correct Usage Pattern

```swift
public func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing errorType: Err.Type,
    returning returnType: Res.Type
) async throws -> Res {
    // 1. Serialize invocation to InvocationEnvelope
    let envelope = InvocationEnvelope(...)

    // 2. Send over transport (BLE, gRPC, etc.)
    let response = try await transport.send(envelope)

    // 3. Create decoder from response
    var decoder = makeDecoder(from: response)

    // 4. Let Swift runtime handle method dispatch
    try await executeDistributedTarget(
        on: actor,
        target: target,
        invocationDecoder: &decoder,
        handler: resultHandler
    )
}
```

The `executeDistributedTarget` method:
- Looks up the distributed function based on the `RemoteCallTarget`
- Decodes arguments efficiently from the `InvocationDecoder`
- Performs the call on the target method
- Handles results via the `ResultHandler`

**No manual method registration required!**

## Design Principles

### 1. Transport Independence

The runtime knows **nothing** about:
- Network protocols (BLE, gRPC, HTTP)
- Connection management
- Discovery mechanisms
- Security/encryption

The runtime only handles:
- Invocation representation
- Actor/method lookup
- Serialization abstraction

### 2. Zero Dependencies

- Pure Swift standard library
- No external packages
- Minimal API surface
- Maximum compatibility

### 3. Thread Safety via Mutex

- No `@unchecked Sendable`
- No `NSLock` (not Sendable)
- Use `Synchronization.Mutex` (Swift 6.0+)
- All registries are `Sendable`

### 4. Type Erasure

- Methods registered as `(Data) async throws -> Data`
- Type safety via `Codable` at boundaries
- Runtime doesn't know about specific types

## Architecture

```
┌─────────────────────────────────────────────┐
│           User Code                          │
│   distributed actor MySensor { }             │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────┴──────────────────────────┐
│     Transport Implementation                 │
│  (BLEActorSystem, GRPCActorSystem, etc.)    │
│                                              │
│  - Connection management                     │
│  - Discovery                                 │
│  - Security                                  │
│  - Protocol-specific optimizations           │
└──────────────────┬──────────────────────────┘
                   │ Uses ActorRuntime
┌──────────────────┴──────────────────────────┐
│       swift-actor-runtime                    │
│                                              │
│  ┌─────────────────────────────────────┐   │
│  │  Envelope System                     │   │
│  │  - InvocationEnvelope                │   │
│  │  - ResponseEnvelope                  │   │
│  │  - InvocationResult                  │   │
│  └─────────────────────────────────────┘   │
│                                              │
│  ┌─────────────────────────────────────┐   │
│  │  Registry System                     │   │
│  │  - ActorRegistry (instance lookup)   │   │
│  └─────────────────────────────────────┘   │
│                                              │
│  ┌─────────────────────────────────────┐   │
│  │  Error System                        │   │
│  │  - RuntimeError (standard errors)    │   │
│  └─────────────────────────────────────┘   │
│                                              │
│  ┌─────────────────────────────────────┐   │
│  │  Transport Protocol                  │   │
│  │  - DistributedTransport interface    │   │
│  │  - Codable envelopes                 │   │
│  └─────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
```

## Component Design

### InvocationEnvelope

**Purpose**: Transport-agnostic representation of a method call

**Fields**:
- `callID: String` - Unique identifier for matching response
- `recipientID: String` - Target actor identifier
- `senderID: String?` - Source actor (optional, for bidirectional)
- `target: String` - Method name (mangled Swift identifier)
- `genericSubstitutions: [String]` - Generic type parameters (mangled type names)
- `arguments: Data` - Serialized arguments
- `metadata: Metadata` - Timestamp, version, headers

**Design decisions**:
- `String` IDs not `UUID` - allows custom ID schemes (UUIDs, names, etc.)
- `Data` for arguments - transport chooses serialization format
- `genericSubstitutions` - enables type-safe generic method calls across network
- `Codable` - works with JSON, Protobuf, MessagePack

### ResponseEnvelope

**Purpose**: Transport-agnostic representation of method result

**Fields**:
- `callID: String` - Matches InvocationEnvelope
- `result: InvocationResult` - Success/void/failure
- `metadata: Metadata` - Timestamp, execution time, headers

**InvocationResult**:
```swift
enum InvocationResult {
    case success(Data)  // Method returned a value
    case void           // Method returned Void
    case failure(RuntimeError)  // Method threw
}
```

### ActorRegistry

**Purpose**: Map actor IDs to instances

**Implementation**:
```swift
final class ActorRegistry: Sendable {
    private struct State {
        var actors: [String: any DistributedActor] = [:]
    }
    private let mutex = Mutex(State())
}
```

**Thread safety**: Mutex ensures safe concurrent access

**Why not `actor`?**:
- ActorSystems are `class` not `actor`
- Need synchronous access
- Mutex provides Sendable without `@unchecked`

### RuntimeError

**Purpose**: Standard, serializable error types

**Cases**:
- `actorNotFound(String)` - Target actor not in registry
- `actorDeallocated(String)` - Actor instance was deallocated
- `methodNotFound(String)` - Distributed method not found (rare, usually a version mismatch)
- `executionFailed(String, underlying: String)` - Method threw
- `serializationFailed(String)` - Encode/decode error
- `transportFailed(String)` - Network error
- `timeout(TimeInterval)` - RPC timeout
- `invalidEnvelope(String)` - Malformed message
- `versionMismatch(expected: String, actual: String)` - Protocol version error

**Codable conformance**: Allows errors to propagate across network

### DistributedTransport Protocol

**Purpose**: Common interface for all transports

**Required methods**:
```swift
protocol DistributedTransport: Sendable {
    // Client side: send invocation, await response
    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope

    // Server side: stream of incoming invocations
    var incomingInvocations: AsyncStream<InvocationEnvelope> { get }

    // Server side: send response
    func sendResponse(_ envelope: ResponseEnvelope) async throws

    // Optional: cleanup
    func close() async throws
}
```

**Separation of concerns**:
- Transport: connectivity, discovery, security, serialization
- Runtime: invocation, routing, errors

**Serialization**: All envelopes conform to Swift's `Codable` protocol. Transport implementations can use any encoder/decoder (JSONEncoder, Protocol Buffers, MessagePack, etc.) to serialize envelopes for transmission.

## Data Flow

### Client → Server (Method Call)

```
1. Client: sensor.readTemperature()
   ↓
2. Transport: Create InvocationEnvelope
   {
     callID: "uuid-1234",
     recipientID: "sensor-1",
     target: "readTemperature",
     arguments: Data()
   }
   ↓
3. Transport: Serialize and send over wire
   (BLE write, gRPC call, HTTP POST, etc.)
   ↓
4. Transport: Deserialize to InvocationEnvelope
   ↓
5. Runtime: Find actor via ActorRegistry
   let actor = actorRegistry.find(id: "sensor-1")
   ↓
6. Runtime: Execute method via executeDistributedTarget
   var decoder = makeDecoder(from: envelope)
   let result = try await executeDistributedTarget(
       on: actor,
       target: envelope.target,
       invocationDecoder: &decoder,
       handler: resultHandler
   )
   ↓
7. Runtime: Create ResponseEnvelope
   {
     callID: "uuid-1234",
     result: .success(resultData)
   }
```

### Server → Client (Response)

```
9. Transport: Serialize ResponseEnvelope
   ↓
10. Transport: Send over wire
    (BLE notification, gRPC response, HTTP response)
    ↓
11. Transport: Deserialize to ResponseEnvelope
    ↓
12. Transport: Match callID to pending call
    ↓
13. Transport: Resume continuation with result
    ↓
14. Client: Receives return value
```

## Thread Safety Model

### Mutex vs NSLock vs Actor

| Approach | Sendable | Async Access | Overhead |
|----------|----------|--------------|----------|
| `NSLock` | ❌ Needs `@unchecked` | ✅ Sync | Low |
| `actor` | ✅ Native | ❌ Async only | Medium |
| `Mutex` | ✅ Native | ✅ Sync | Low |

**Choice**: `Mutex` - Sendable + synchronous + low overhead

### Lock Granularity

**Per-registry state**:
```swift
private struct State {
    var actors: [String: any DistributedActor] = [:]
}
private let mutex = Mutex(State())
```

**Why**: Minimizes lock contention, allows parallel access to different registries

## Serialization Strategy

All envelopes (`InvocationEnvelope`, `ResponseEnvelope`, `RuntimeError`) conform to Swift's `Codable` protocol. Transport implementations choose their own serialization format:

### Common Formats:

**JSON** (via `JSONEncoder`/`JSONDecoder`):
- ✅ Human-readable (debugging)
- ✅ Universal support
- ✅ No dependencies
- ❌ Larger payload
- ❌ Slower than binary

**Protocol Buffers** (via SwiftProtobuf):
- ✅ Compact binary
- ✅ Schema versioning
- ✅ Fast
- ❌ Requires protobuf dependency
- ❌ Not human-readable

**MessagePack** (via third-party libraries):
- ✅ Compact binary
- ✅ Simple format
- ❌ Additional dependency

The runtime library itself is serialization-agnostic. Transport implementations simply call:
```swift
let data = try JSONEncoder().encode(envelope)
// or
let data = try envelope.serializedData() // Protocol Buffers
```

## Performance Considerations

### Registry Lookups

- **Complexity**: O(1) dictionary lookup
- **Overhead**: ~1-2μs for mutex lock/unlock
- **Context**: Negligible vs network latency (10-100ms)

### Memory

Per actor:
- ActorRegistry entry: ~32 bytes (pointer + UUID)

Typical peripheral (1 actor, 5 methods): ~32 bytes overhead

### Scalability

- **Actors**: Tested to 10,000+ actors per registry
- **Methods**: Tested to 100+ methods per actor
- **Concurrent calls**: Thread-safe, no bottleneck

## Error Handling Strategy

### Error Propagation

```
Peripheral throws error
   ↓
executeDistributedTarget catches, wraps in RuntimeError
   ↓
ResponseEnvelope.result = .failure(error)
   ↓
Serialize and send to central
   ↓
Central deserializes RuntimeError
   ↓
Central throws to caller
```

### Error Types

**User errors** (expected):
- `actorNotFound` - Client requested non-existent actor
- `methodNotFound` - Distributed method doesn't exist (version mismatch)
- `executionFailed` - Method logic threw

**System errors** (unexpected):
- `serializationFailed` - Codable conformance issue
- `transportFailed` - Network issue
- `invalidEnvelope` - Protocol corruption

## Versioning Strategy

### Protocol Versioning

```swift
struct InvocationEnvelope {
    let metadata: Metadata

    struct Metadata {
        let version: String  // e.g., "1.0"
    }
}
```

**Compatibility checks**:
```swift
guard envelope.metadata.version == "1.0" else {
    throw RuntimeError.versionMismatch(expected: "1.0", actual: envelope.metadata.version)
}
```

### Semantic Versioning

- `1.0.0` - Initial release
- `1.1.0` - Add optional fields (backward compatible)
- `2.0.0` - Breaking changes (rare)

### Backward Compatibility

- Optional fields default to nil
- New error cases are non-breaking
- Metadata headers for extensions

## Testing Strategy

### Unit Tests

- ✅ Envelope encoding/decoding
- ✅ Registry thread safety
- ✅ Error serialization
- ✅ Concurrent access patterns

### Integration Tests

- ✅ Full RPC flow (mock transport)
- ✅ Error propagation
- ✅ Timeout handling
- ✅ Multiple simultaneous calls

### Performance Tests

- ✅ Registry lookup latency
- ✅ Serialization overhead
- ✅ Memory usage

## Migration Path

### From Bleu

**Before** (Bleu internal types):
```swift
struct InvocationEnvelope { ... }  // In BleuTypes.swift
```

**After** (ActorRuntime):
```swift
import ActorRuntime
// Use ActorRuntime.InvocationEnvelope
```

**Changes**:
1. Add dependency on swift-actor-runtime
2. Remove duplicate types from BleuTypes.swift
3. Update imports
4. Use ActorRegistry for instance tracking
5. Use executeDistributedTarget for method dispatch

### From Actor-Edge

Similar migration, map Protobuf messages to runtime envelopes

## Generic Method Support

The runtime provides full support for distributed methods with generic type parameters and generic distributed actors.

### Generic Methods

Distributed actors can define methods with generic type parameters:

```swift
distributed actor DataStore {
    typealias ActorSystem = InMemoryActorSystem

    distributed func store<T: Codable>(_ value: T, key: String) { ... }
    distributed func fetch<T: Codable>(key: String) -> T? { ... }
}
```

### Generic Actors

Distributed actors can themselves be generic:

```swift
distributed actor GenericContainer<T: Codable & Sendable> {
    typealias ActorSystem = InMemoryActorSystem

    private var value: T

    distributed func getValue() -> T { return value }
    distributed func setValue(_ newValue: T) { value = newValue }
}
```

### Implementation Details

1. **Type Recording**: The encoder records generic type substitutions via `recordGenericSubstitution<T>(_:)`
2. **Type Transmission**: Mangled type names are stored in `InvocationEnvelope.genericSubstitutions`
3. **Type Resolution**: The decoder uses Swift's `_typeByName()` to resolve mangled names back to types
4. **Type Safety**: Swift's runtime ensures type-safe dispatch using the resolved generic types

### Constraints

- All generic type parameters must conform to `Codable`
- For generic actor type parameters, types must also conform to `Sendable`
- Closures cannot be used as distributed method parameters (not `Codable`)

## Future Enhancements

### Phase 1: Core (v1.0)
- ✅ Envelopes
- ✅ Registries
- ✅ Errors
- ✅ Transport protocol
- ✅ Generic method support
- ✅ Generic actor support

### Phase 2: Advanced (v1.1)
- ⏳ Streaming support (`AsyncStream` results)
- ⏳ Metrics/observability hooks
- ⏳ Compression support

### Phase 3: Ecosystem (v2.0)
- ⏳ Macro-based method registration (Swift 6+)
- ⏳ Cross-transport bridging
- ⏳ Load balancing primitives

## References

- [Swift Distributed Actors (SE-0336)](https://github.com/apple/swift-evolution/blob/main/proposals/0336-distributed-actor-isolation.md)
- [Swift Synchronization (SE-0433)](https://github.com/apple/swift-evolution/blob/main/proposals/0433-mutex.md)
- [Actor-Edge](https://github.com/1amageek/actor-edge) - gRPC implementation
- [Bleu](https://github.com/1amageek/Bleu) - BLE implementation
