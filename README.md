# Swift Actor Runtime

[![Test](https://github.com/1amageek/swift-actor-runtime/actions/workflows/test.yml/badge.svg)](https://github.com/1amageek/swift-actor-runtime/actions/workflows/test.yml)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Transport-agnostic primitives for implementing Swift Distributed Actor systems.

## Overview

`swift-actor-runtime` provides the foundational building blocks needed by any distributed actor system implementation, regardless of transport layer (BLE, gRPC, HTTP/2, WebSocket, etc.).

**Vision**: "Write once, run on any transport"

### Who Is This For?

| Audience | Use Case |
|----------|----------|
| **Transport Authors** | Building a new distributed actor transport (e.g., MQTT, WebSocket, custom protocol). This library provides all the common infrastructure so you can focus on connectivity. |
| **App Developers** | Using an existing transport (Bleu, ActorEdge). You don't need to use this library directly—it's a dependency of your transport. |

### When to Use This Library

**Use this library if you are:**
- Implementing a new `DistributedActorSystem` for a specific protocol
- Building infrastructure that needs to serialize/deserialize distributed actor calls
- Creating a transport-agnostic layer for your distributed system

**You probably don't need this library directly if you are:**
- Building apps using existing transports like Bleu or ActorEdge
- Just defining distributed actors for your application

## Features

- ✅ **Universal Envelopes**: `InvocationEnvelope` and `ResponseEnvelope` for method calls
- ✅ **Actor Registry**: Thread-safe actor instance tracking via `Mutex`
- ✅ **Codable Codec**: Complete `InvocationEncoder`/`Decoder` implementation for Codable arguments
- ✅ **Generic Method Support**: Full support for distributed methods with generic type parameters
- ✅ **Generic Actor Support**: Support for distributed actors with generic constraints
- ✅ **Swift Runtime Integration**: Uses `executeDistributedTarget` for method dispatch
- ✅ **Standard Errors**: Serializable `RuntimeError` types
- ✅ **Transport Protocol**: Common interface for all transport implementations
- ✅ **Error Propagation**: `AsyncThrowingStream` for transport-level error handling
- ✅ **Zero Dependencies**: Pure Swift standard library
- ✅ **Sendable-Safe**: Full Swift 6 concurrency support

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-actor-runtime", from: "0.3.0")
]
```

## Quick Start

### Using a Transport (e.g., Bleu for BLE)

```swift
import ActorRuntime
import Bleu  // or any other transport

// Define your distributed actor
distributed actor TemperatureSensor {
    typealias ActorSystem = BLEActorSystem

    distributed func readTemperature() async -> Double {
        return 22.5
    }
}

// Server (Peripheral)
let system = BLEActorSystem.mock()
let sensor = TemperatureSensor(actorSystem: system)
try await system.startAdvertising(sensor)

// Client (Central)
let system = BLEActorSystem.mock()
let sensors = try await system.discover(TemperatureSensor.self)
let temp = try await sensors[0].readTemperature()
```

### Implementing a Transport

```swift
import ActorRuntime

public final class MyTransport: DistributedTransport {
    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        // Your transport-specific code here
        // 1. Serialize envelope
        // 2. Send over your protocol (BLE, HTTP, etc.)
        // 3. Await response
        // 4. Return ResponseEnvelope
    }

    public var incomingInvocations: AsyncThrowingStream<InvocationEnvelope, Error> {
        AsyncThrowingStream { continuation in
            // Listen for incoming RPCs on your transport
            // Use continuation.finish(throwing:) for transport errors
        }
    }

    public func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Send response back to caller
    }
}
```

## Architecture

```
┌──────────────────────────────────┐
│    Your Distributed Actors       │
└────────────┬─────────────────────┘
             │
┌────────────┴─────────────────────┐
│    Transport Implementation      │
│   (Bleu, ActorEdge, Custom)      │
└────────────┬─────────────────────┘
             │
┌────────────┴─────────────────────┐
│    swift-actor-runtime           │
│  ┌────────────────────────────┐  │
│  │ InvocationEnvelope         │  │
│  │ ResponseEnvelope           │  │
│  │ ActorRegistry              │  │
│  │ CodableInvocationEncoder   │  │
│  │ CodableInvocationDecoder   │  │
│  │ RuntimeError               │  │
│  │ DistributedTransport       │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

## Core Components

### InvocationEnvelope

Represents a distributed method call:

```swift
let envelope = InvocationEnvelope(
    recipientID: "sensor-1",
    target: "readTemperature",
    genericSubstitutions: [], // Optional: for generic methods
    arguments: Data()
)
```

For generic methods, the envelope automatically captures type substitutions to ensure type-safe distributed calls.

### ResponseEnvelope

Represents the result:

```swift
let response = ResponseEnvelope(
    callID: envelope.callID,
    result: .success(resultData)
)
```

### ActorRegistry

Tracks actor instances:

```swift
let registry = ActorRegistry()
registry.register(sensor, id: "sensor-1")

if let actor = registry.find(id: "sensor-1") {
    // Execute method on actor
}

// Important: Cleanup when done to prevent memory leaks
registry.unregister(id: "sensor-1")

// Or clear all actors during shutdown
registry.clear()
```

**Memory Management**: `ActorRegistry` maintains strong references. Always call `unregister(id:)` when actors are no longer needed to prevent memory leaks.

### RuntimeError

Standard error types:

```swift
throw RuntimeError.actorNotFound("sensor-1")
throw RuntimeError.methodNotFound("readTemperature")
throw RuntimeError.timeout(10.0)
```

### Error Handling

The `incomingInvocations` stream uses `AsyncThrowingStream` to propagate transport-level errors:

```swift
// In your ActorSystem's server loop
do {
    for try await envelope in transport.incomingInvocations {
        // Handle incoming invocation
        await handleInvocation(envelope)
    }
} catch {
    // Handle transport errors (connection lost, deserialization failed, etc.)
    print("Transport error: \(error)")
}
```

Transport implementations can signal errors using the continuation:

```swift
public var incomingInvocations: AsyncThrowingStream<InvocationEnvelope, Error> {
    AsyncThrowingStream { continuation in
        // On successful message
        continuation.yield(envelope)

        // On transport error
        continuation.finish(throwing: TransportError.connectionLost)

        // On clean shutdown
        continuation.finish()
    }
}
```

## Platform Support

- Swift 6.2+
- iOS 18.0+
- macOS 15.0+
- watchOS 11.0+
- tvOS 18.0+
- visionOS 2.0+

## Transports Using This Runtime

- [Bleu](https://github.com/1amageek/Bleu) - BLE (Bluetooth Low Energy)
- [ActorEdge](https://github.com/1amageek/actor-edge) - gRPC
- *Your transport here!*

## Codec System

### CodableInvocationEncoder / Decoder

The Codec system enables distributed method calls with Codable arguments:

```swift
// In your DistributedActorSystem implementation
func remoteCall<Act, Err, Res>(
    on actor: Act,
    target: RemoteCallTarget,
    invocation: inout InvocationEncoder,
    throwing: Err.Type,
    returning: Res.Type
) async throws -> Res {
    var encoder = invocation as! CodableInvocationEncoder
    encoder.recordTarget(target)

    let envelope = try encoder.makeInvocationEnvelope(
        recipientID: actor.id.description
    )

    // Send envelope over your transport...
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

See [Examples/InMemoryTransport.swift](Examples/InMemoryTransport.swift) for a complete working implementation.

## Documentation

- [Design Documentation](Documentation/DESIGN.md) - Detailed architecture and design decisions
- [Codec System Design](Documentation/CODEC.md) - InvocationEncoder/Decoder implementation details
- [InMemoryTransport Example](Examples/InMemoryTransport.swift) - Complete working transport implementation

## License

MIT License

## Author

[@1amageek](https://github.com/1amageek)
