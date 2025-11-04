# Swift Actor Runtime - Design Document

## Problem Statement

Swift's Distributed Actor system provides excellent abstractions for writing distributed code, but:

1. **No public reflection APIs**: `executeDistributedTarget` delegates to internal runtime
2. **Transport coupling**: Each implementation re-invents envelopes, registries, errors
3. **Code duplication**: Common patterns repeated across projects
4. **Ecosystem fragmentation**: Hard to switch transports or mix them

## Solution

Extract transport-agnostic primitives into a shared runtime library that:
- Provides standard envelopes for RPC
- Manages actor instance and method registries
- Defines common error types
- Establishes transport protocol interface

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
│  │  - MethodRegistry (execution)        │   │
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
│  └─────────────────────────────────────┘   │
│                                              │
│  ┌─────────────────────────────────────┐   │
│  │  Serialization System                │   │
│  │  - SerializationSystem protocol      │   │
│  │  - JSONSerializationSystem           │   │
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
- `arguments: Data` - Serialized arguments
- `metadata: Metadata` - Timestamp, version, headers

**Design decisions**:
- `String` IDs not `UUID` - allows custom ID schemes (UUIDs, names, etc.)
- `Data` for arguments - transport chooses serialization format
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

### MethodRegistry

**Purpose**: Execute methods by name without reflection

**Implementation**:
```swift
final class MethodRegistry: Sendable {
    typealias MethodHandler = @Sendable (Data) async throws -> Data

    private struct State {
        var methods: [String: MethodHandler] = [:]
    }
    private let mutex = Mutex(State())
}
```

**Why needed**: Swift doesn't expose APIs to execute distributed methods by name

**Registration pattern**:
```swift
// Actor registers its methods
distributed actor Sensor {
    distributed func read() async -> Double { 22.5 }

    func registerMethods(with registry: MethodRegistry) async {
        await registry.register("read") { [weak self] _ in
            guard let self = self else { throw RuntimeError.actorDeallocated("sensor") }
            let result = try await self.read()
            return try JSONEncoder().encode(result)
        }
    }
}
```

### RuntimeError

**Purpose**: Standard, serializable error types

**Cases**:
- `actorNotFound(String)` - Target actor not in registry
- `actorDeallocated(String)` - Actor instance was deallocated
- `methodNotFound(String)` - Method not registered
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
- Transport: connectivity, discovery, security
- Runtime: invocation, routing, errors

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
6. Runtime: Find method via MethodRegistry
   let methodRegistry = methodRegistries["sensor-1"]
   ↓
7. Runtime: Execute method
   let resultData = try await methodRegistry.execute("readTemperature", args: Data())
   ↓
8. Runtime: Create ResponseEnvelope
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

### Pluggable System

```swift
protocol SerializationSystem: Sendable {
    func encode<T: Encodable>(_ value: T) throws -> Data
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}
```

### Default: JSON

**Pros**:
- Human-readable (debugging)
- Universal support
- No dependencies

**Cons**:
- Larger payload
- Slower than binary

### Alternative: Protocol Buffers

**Pros**:
- Compact binary
- Schema versioning
- Fast

**Cons**:
- Requires protobuf dependency
- Not human-readable

**Choice**: JSON default, Protobuf optional

## Performance Considerations

### Registry Lookups

- **Complexity**: O(1) dictionary lookup
- **Overhead**: ~1-2μs for mutex lock/unlock
- **Context**: Negligible vs network latency (10-100ms)

### Memory

Per actor:
- ActorRegistry entry: ~32 bytes (pointer + UUID)
- MethodRegistry instance: ~100 bytes
- Per method: ~100 bytes (closure)

Typical peripheral (1 actor, 5 methods): ~600 bytes overhead

### Scalability

- **Actors**: Tested to 10,000+ actors per registry
- **Methods**: Tested to 100+ methods per actor
- **Concurrent calls**: Thread-safe, no bottleneck

## Error Handling Strategy

### Error Propagation

```
Peripheral throws error
   ↓
MethodRegistry catches, wraps in RuntimeError
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
- `methodNotFound` - Actor doesn't have method
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
4. Use ActorRegistry/MethodRegistry

### From Actor-Edge

Similar migration, map Protobuf messages to runtime envelopes

## Future Enhancements

### Phase 1: Core (v1.0)
- ✅ Envelopes
- ✅ Registries
- ✅ Errors
- ✅ Transport protocol

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
