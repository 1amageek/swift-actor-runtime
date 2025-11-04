# Swift Actor Runtime

Transport-agnostic primitives for implementing Swift Distributed Actor systems.

## Overview

`swift-actor-runtime` provides the foundational building blocks needed by any distributed actor system implementation, regardless of transport layer (BLE, gRPC, HTTP/2, WebSocket, etc.).

**Vision**: "Write once, run on any transport"

## Features

- ✅ **Universal Envelopes**: `InvocationEnvelope` and `ResponseEnvelope` for method calls
- ✅ **Actor Registry**: Thread-safe actor instance tracking via `Mutex`
- ✅ **Method Registry**: Execute distributed methods without reflection
- ✅ **Standard Errors**: Serializable `RuntimeError` types
- ✅ **Transport Protocol**: Common interface for all transport implementations
- ✅ **Pluggable Serialization**: JSON (default), Protocol Buffers, or custom
- ✅ **Zero Dependencies**: Pure Swift standard library
- ✅ **Sendable-Safe**: Full Swift 6 concurrency support

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-actor-runtime", from: "1.0.0")
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

    public var incomingInvocations: AsyncStream<InvocationEnvelope> {
        AsyncStream { continuation in
            // Listen for incoming RPCs on your transport
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
│  │ MethodRegistry             │  │
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
    arguments: Data()
)
```

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

### MethodRegistry

Executes methods by name:

```swift
let registry = MethodRegistry()

registry.register("readTemperature") { argsData in
    let result = try await self.readTemperature()
    return try JSONEncoder().encode(result)
}

let resultData = try await registry.execute("readTemperature", arguments: Data())
```

### RuntimeError

Standard error types:

```swift
throw RuntimeError.actorNotFound("sensor-1")
throw RuntimeError.methodNotFound("readTemperature")
throw RuntimeError.timeout(10.0)
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

## Documentation

- [Design Documentation](Documentation/DESIGN.md) - Detailed architecture and design decisions

## License

MIT License

## Author

[@1amageek](https://github.com/1amageek)
