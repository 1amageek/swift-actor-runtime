# Transport Implementation Guide

This guide provides best practices and patterns for implementing a custom transport layer for `swift-actor-runtime`.

## Overview

A transport implementation is responsible for:
- Sending invocations to remote actors
- Receiving invocations from remote callers
- Routing responses back to the correct caller
- Managing the underlying network protocol (BLE, gRPC, HTTP, etc.)

The runtime provides all the primitives you need through:
- `InvocationEnvelope` and `ResponseEnvelope` for RPC messages
- `CodableInvocationEncoder` and `CodableInvocationDecoder` for argument encoding/decoding
- `CodableResultHandler` for capturing method results
- `ActorRegistry` for managing actor instances

## Server-Side Patterns

### Pattern 1: Direct Response (Simple Request-Response)

Use this pattern for simple request-response transports where you can directly send the response back through the same connection (HTTP, WebSocket).

```swift
import ActorRuntime
import Distributed

class MyActorSystem: DistributedActorSystem {
    typealias ActorID = String
    typealias InvocationEncoder = CodableInvocationEncoder
    typealias InvocationDecoder = CodableInvocationDecoder
    typealias ResultHandler = CodableResultHandler
    typealias SerializationRequirement = Codable

    private let registry = ActorRegistry()
    private let transport: MyTransport

    // Server-side: Handle incoming invocations
    func startServer() async throws {
        for await envelope in transport.incomingInvocations {
            // Handle each invocation in a separate task
            Task {
                await handleInvocation(envelope)
            }
        }
    }

    private func handleInvocation(_ envelope: InvocationEnvelope) async {
        do {
            // Find the target actor
            guard let actor = registry.find(id: envelope.recipientID) else {
                let errorResponse = ResponseEnvelope(
                    callID: envelope.callID,
                    result: .failure(.actorNotFound(envelope.recipientID))
                )
                try await transport.sendResponse(errorResponse)
                return
            }

            // Create result handler that sends response directly
            let resultHandler = CodableResultHandler(callID: envelope.callID) { response in
                try await self.transport.sendResponse(response)
            }

            // Execute the distributed method
            var decoder = try CodableInvocationDecoder(envelope: envelope)
            let target = try RemoteCallTarget(identifier: envelope.target)

            try await executeDistributedTarget(
                on: actor,
                target: target,
                invocationDecoder: &decoder,
                handler: resultHandler
            )
        } catch {
            // Send error response if anything goes wrong
            let errorResponse = ResponseEnvelope(
                callID: envelope.callID,
                result: .failure(.transportFailed(String(describing: error)))
            )
            try? await transport.sendResponse(errorResponse)
        }
    }
}
```

**When to use:**
- ✅ HTTP/REST APIs
- ✅ WebSocket connections
- ✅ Simple RPC protocols
- ✅ Direct client-server communication

### Pattern 2: Captured Response (gRPC, Complex Protocols)

Use this pattern when you need to process or enrich the response before sending (add execution time, tracing headers, etc.).

This is the pattern used in ActorEdge (gRPC implementation).

```swift
import ActorRuntime
import Distributed

class MyActorSystem: DistributedActorSystem {
    typealias ActorID = String
    typealias InvocationEncoder = CodableInvocationEncoder
    typealias InvocationDecoder = CodableInvocationDecoder
    typealias ResultHandler = CodableResultHandler
    typealias SerializationRequirement = Codable

    private let registry = ActorRegistry()

    // Handle a single invocation and return the enriched response
    func handleInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        let startTime = Date()

        // Find the target actor
        guard let actor = registry.find(id: envelope.recipientID) else {
            return ResponseEnvelope(
                callID: envelope.callID,
                result: .failure(.actorNotFound(envelope.recipientID))
            )
        }

        // Capture the response in a variable
        var capturedResponse: ResponseEnvelope?
        let resultHandler = CodableResultHandler(callID: envelope.callID) { response in
            capturedResponse = response
        }

        // Execute the distributed method
        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let target = try RemoteCallTarget(identifier: envelope.target)

        try await executeDistributedTarget(
            on: actor,
            target: target,
            invocationDecoder: &decoder,
            handler: resultHandler
        )

        // Ensure we captured a response
        guard let response = capturedResponse else {
            throw RuntimeError.executionFailed(
                "No response captured",
                underlying: "Internal error: executeDistributedTarget did not produce a response"
            )
        }

        // Enrich response with execution time and tracing information
        let executionTime = Date().timeIntervalSince(startTime)
        return response
            .withExecutionTime(executionTime)
            .withHeader("method", value: envelope.target)
            .withHeader("trace-id", value: envelope.metadata.headers["trace-id"] ?? "")
    }
}
```

**When to use:**
- ✅ gRPC implementations (like ActorEdge)
- ✅ When you need to measure execution time
- ✅ When you need to add tracing headers
- ✅ When response needs post-processing before sending
- ✅ When integrating with observability systems

**Key benefits:**
- Can measure execution time accurately
- Can add contextual metadata to responses
- Can integrate with distributed tracing systems
- Clean separation between execution and response handling

## Client-Side Pattern

```swift
import ActorRuntime
import Distributed

class MyActorSystem: DistributedActorSystem {
    // ... typealias definitions ...

    private let transport: MyTransport
    private let registry = ActorRegistry()

    // Client-side: Make a remote call
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor {
        // Cast to our concrete encoder
        var encoder = invocation as! CodableInvocationEncoder

        // Record the target method
        encoder.recordTarget(target)

        // Create the invocation envelope
        let envelope = try encoder.makeInvocationEnvelope(
            recipientID: actor.id.description,
            senderID: nil
        )

        // Send via transport and await response
        let response = try await transport.sendInvocation(envelope)

        // Decode and return the result
        switch response.result {
        case .success(let data):
            return try JSONDecoder().decode(Res.self, from: data)
        case .void:
            return () as! Res
        case .failure(let error):
            throw error
        }
    }

    // Similar implementation for remoteCallVoid
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws where Act: DistributedActor {
        var encoder = invocation as! CodableInvocationEncoder
        encoder.recordTarget(target)

        let envelope = try encoder.makeInvocationEnvelope(
            recipientID: actor.id.description,
            senderID: nil
        )

        let response = try await transport.sendInvocation(envelope)

        switch response.result {
        case .success, .void:
            return
        case .failure(let error):
            throw error
        }
    }
}
```

## Best Practices

### 1. Always Handle Actor Not Found

```swift
guard let actor = registry.find(id: envelope.recipientID) else {
    let errorResponse = ResponseEnvelope(
        callID: envelope.callID,
        result: .failure(.actorNotFound(envelope.recipientID))
    )
    try await transport.sendResponse(errorResponse)
    return
}
```

### 2. Track Execution Time

```swift
let startTime = Date()
// ... execute method ...
let executionTime = Date().timeIntervalSince(startTime)
let enrichedResponse = response.withExecutionTime(executionTime)
```

### 3. Add Distributed Tracing Headers

```swift
let enrichedResponse = response
    .withHeader("trace-id", value: envelope.metadata.headers["trace-id"] ?? "")
    .withHeader("span-id", value: UUID().uuidString)
    .withHeader("method", value: envelope.target)
```

### 4. Handle Errors Gracefully

```swift
do {
    try await executeDistributedTarget(...)
} catch let error as RuntimeError {
    // Runtime errors are already properly formatted
    let errorResponse = ResponseEnvelope(
        callID: envelope.callID,
        result: .failure(error)
    )
    try await transport.sendResponse(errorResponse)
} catch {
    // Wrap unexpected errors
    let errorResponse = ResponseEnvelope(
        callID: envelope.callID,
        result: .failure(.executionFailed(
            String(describing: error),
            underlying: String(reflecting: error)
        ))
    )
    try await transport.sendResponse(errorResponse)
}
```

### 5. Use Concurrent Tasks for Server-Side Handling

```swift
func startServer() async throws {
    for await envelope in transport.incomingInvocations {
        // Handle each invocation concurrently
        Task {
            await handleInvocation(envelope)
        }
    }
}
```

This allows multiple invocations to be processed in parallel without blocking.

### 6. Register and Unregister Actors Properly

```swift
// Register when actor is created
func resolve<Act>(id: ActorID, using behavior: Act) throws -> Act?
    where Act: DistributedActor {
    registry.register(actor: behavior, id: id)
    return nil
}

// Unregister when actor is deallocated
func resignID(_ id: ActorID) {
    registry.unregister(id: id)
}
```

## Error Handling Strategy

### Transport-Level Errors

Use `RuntimeError.transportFailed` for network-related errors:

```swift
catch {
    let errorResponse = ResponseEnvelope(
        callID: envelope.callID,
        result: .failure(.transportFailed("Connection lost: \(error)"))
    )
    try await transport.sendResponse(errorResponse)
}
```

### Serialization Errors

The codec system automatically throws `RuntimeError.serializationFailed` with detailed information:

```swift
// This will throw with method name and type information
var decoder = try CodableInvocationDecoder(envelope: envelope)
let arg: Int = try decoder.decodeNextArgument()
```

### Method Execution Errors

User errors are automatically wrapped in `RuntimeError.executionFailed`:

```swift
distributed func myMethod() throws {
    throw MyError()  // Automatically wrapped in RuntimeError
}
```

## Complete Example: Simple HTTP Transport

```swift
import ActorRuntime
import Distributed
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

class HTTPActorSystem: DistributedActorSystem {
    typealias ActorID = String
    typealias InvocationEncoder = CodableInvocationEncoder
    typealias InvocationDecoder = CodableInvocationDecoder
    typealias ResultHandler = CodableResultHandler
    typealias SerializationRequirement = Codable

    private let registry = ActorRegistry()
    private let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    // Client-side: Send invocation via HTTP POST
    func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor {
        var encoder = invocation as! CodableInvocationEncoder
        encoder.recordTarget(target)

        let envelope = try encoder.makeInvocationEnvelope(
            recipientID: actor.id.description
        )

        // Serialize envelope to JSON
        let requestData = try JSONEncoder().encode(envelope)

        // Send HTTP POST
        var request = URLRequest(url: baseURL.appendingPathComponent("/invoke"))
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)

        // Decode response
        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        switch response.result {
        case .success(let data):
            return try JSONDecoder().decode(Res.self, from: data)
        case .void:
            return () as! Res
        case .failure(let error):
            throw error
        }
    }

    // Server-side: Handle HTTP POST to /invoke
    func handleHTTPRequest(data: Data) async throws -> Data {
        // Decode invocation envelope
        let envelope = try JSONDecoder().decode(InvocationEnvelope.self, from: data)

        // Use Pattern 2: Captured Response
        let startTime = Date()

        guard let actor = registry.find(id: envelope.recipientID) else {
            let errorResponse = ResponseEnvelope(
                callID: envelope.callID,
                result: .failure(.actorNotFound(envelope.recipientID))
            )
            return try JSONEncoder().encode(errorResponse)
        }

        var capturedResponse: ResponseEnvelope?
        let resultHandler = CodableResultHandler(callID: envelope.callID) { response in
            capturedResponse = response
        }

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let target = try RemoteCallTarget(identifier: envelope.target)

        try await executeDistributedTarget(
            on: actor,
            target: target,
            invocationDecoder: &decoder,
            handler: resultHandler
        )

        guard let response = capturedResponse else {
            throw RuntimeError.executionFailed("No response captured", underlying: "Internal error")
        }

        let executionTime = Date().timeIntervalSince(startTime)
        let enrichedResponse = response.withExecutionTime(executionTime)

        return try JSONEncoder().encode(enrichedResponse)
    }

    // Required DistributedActorSystem methods
    func resolve<Act>(id: ActorID, using behavior: Act) throws -> Act?
        where Act: DistributedActor {
        registry.register(actor: behavior, id: id)
        return nil
    }

    func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
        return UUID().uuidString
    }

    func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
        // Actor is ready to receive calls
    }

    func resignID(_ id: ActorID) {
        registry.unregister(id: id)
    }

    func makeInvocationEncoder() -> InvocationEncoder {
        return CodableInvocationEncoder()
    }
}
```

## Testing Your Transport

### Unit Tests

Test the envelope serialization/deserialization:

```swift
@Test("Envelope serialization round-trip")
func testEnvelopeSerialization() throws {
    let original = InvocationEnvelope(
        recipientID: "actor-1",
        target: "testMethod",
        arguments: []
    )

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(InvocationEnvelope.self, from: data)

    #expect(decoded.recipientID == original.recipientID)
    #expect(decoded.target == original.target)
}
```

### Integration Tests

Test the full RPC flow:

```swift
@Test("Full RPC round-trip")
func testFullRPC() async throws {
    distributed actor TestActor {
        typealias ActorSystem = MyActorSystem

        distributed func add(_ a: Int, _ b: Int) -> Int {
            return a + b
        }
    }

    let system = MyActorSystem()
    let actor = TestActor(actorSystem: system)

    let result = try await actor.add(2, 3)
    #expect(result == 5)
}
```

## References

- [DESIGN.md](DESIGN.md) - Architecture and design principles
- [CODEC.md](CODEC.md) - Detailed codec system documentation
- [Bleu](https://github.com/1amageek/Bleu) - BLE transport example
- [ActorEdge](https://github.com/1amageek/actor-edge) - gRPC transport example
