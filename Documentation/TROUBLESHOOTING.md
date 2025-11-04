# Troubleshooting Guide

This guide helps you diagnose and fix common issues when working with `swift-actor-runtime`.

## Table of Contents

- [Serialization Errors](#serialization-errors)
- [Actor Lookup Errors](#actor-lookup-errors)
- [Generic Type Errors](#generic-type-errors)
- [Transport Errors](#transport-errors)
- [Debugging Techniques](#debugging-techniques)

---

## Serialization Errors

### Error: "Failed to decode argument at index X as TYPE for method 'METHOD'"

**Cause**: Type mismatch between sender and receiver.

**Example Error**:
```
RuntimeError.serializationFailed("Failed to decode argument at index 0 as Int for method 'readTemperature': Expected to decode Int but found String instead.")
```

**Common Causes**:

1. **Argument type mismatch**:
   ```swift
   // Sender
   distributed func readTemperature(_ sensorID: String) -> Double

   // Receiver (wrong!)
   distributed func readTemperature(_ sensorID: Int) -> Double
   ```

2. **Argument order mismatch**:
   ```swift
   // Sender
   distributed func store(_ value: Int, key: String)

   // Receiver (wrong order!)
   distributed func store(_ key: String, value: Int)
   ```

3. **Optional vs non-optional mismatch**:
   ```swift
   // Sender
   distributed func getValue() -> String?

   // Receiver (wrong!)
   distributed func getValue() -> String
   ```

**Solutions**:

1. **Verify method signatures match exactly**:
   ```swift
   // Both sides must match
   distributed func readTemperature(_ sensorID: String) -> Double
   ```

2. **Check argument order**:
   ```swift
   // Ensure parameter order is identical
   distributed func store(_ value: Int, key: String)
   ```

3. **Use consistent optional types**:
   ```swift
   // Use same optionality
   distributed func getValue() -> String?
   ```

4. **Add protocol versioning**:
   ```swift
   // Check protocol version before calling
   guard envelope.metadata.version == "1.0" else {
       throw RuntimeError.versionMismatch(expected: "1.0", actual: envelope.metadata.version)
   }
   ```

---

### Error: "Attempted to decode argument at index X, but only Y arguments available"

**Cause**: Sender sent fewer arguments than receiver expects.

**Example Error**:
```
RuntimeError.serializationFailed("Attempted to decode argument at index 2, but only 1 arguments available for method 'calculateSum'")
```

**Common Causes**:

1. **Missing arguments in sender**:
   ```swift
   // Sender (wrong - missing second argument!)
   var encoder = CodableInvocationEncoder()
   try encoder.recordValue(42)

   // Receiver expects two arguments
   distributed func add(_ a: Int, _ b: Int) -> Int
   ```

2. **Default parameter mismatch**:
   ```swift
   // Default parameters are NOT automatically sent!
   distributed func greet(_ name: String, greeting: String = "Hello")

   // Sender must explicitly provide both arguments
   ```

**Solutions**:

1. **Ensure all arguments are recorded**:
   ```swift
   var encoder = CodableInvocationEncoder()
   try encoder.recordValue(42)
   try encoder.recordValue(10)  // Don't forget second argument!
   ```

2. **Make default parameters explicit**:
   ```swift
   // Sender must always provide all arguments
   distributed func greet(_ name: String, greeting: String)
   ```

---

## Actor Lookup Errors

### Error: "Actor not found: ACTOR_ID"

**Cause**: Actor is not registered in the registry or has been deallocated.

**Common Causes**:

1. **Actor not registered before use**:
   ```swift
   // Wrong - actor not registered
   let actor = MyActor(actorSystem: system)
   // ... actor is not in registry yet!
   ```

2. **Actor deallocated prematurely**:
   ```swift
   func createActor() -> MyActor {
       let actor = MyActor(actorSystem: system)
       return actor
   }  // Actor deallocated when scope ends!
   ```

3. **Typo in actor ID**:
   ```swift
   let envelope = InvocationEnvelope(
       recipientID: "sensor-1",  // Typo?
       target: "readTemperature",
       arguments: data
   )
   ```

**Solutions**:

1. **Ensure actor is registered**:
   ```swift
   let actor = MyActor(actorSystem: system)
   // DistributedActorSystem.resolve() is called automatically
   // Actor is now in registry
   ```

2. **Keep strong reference to actor**:
   ```swift
   class MyServer {
       var actors: [String: MyActor] = [:]

       func createActor(id: String) {
           let actor = MyActor(actorSystem: system)
           actors[id] = actor  // Keep strong reference!
       }
   }
   ```

3. **Verify actor ID matches**:
   ```swift
   // Use consistent ID format
   let actorID = "sensor-1"
   let actor = MyActor(actorSystem: system)
   registry.register(actor: actor, id: actorID)

   // Later, use exact same ID
   let envelope = InvocationEnvelope(
       recipientID: actorID,  // Use same ID!
       target: "readTemperature",
       arguments: data
   )
   ```

4. **Clean up properly**:
   ```swift
   deinit {
       // Unregister when actor is deallocated
       registry.unregister(id: id)
   }
   ```

---

## Generic Type Errors

### Error: "Failed to resolve generic type from mangled name: TYPE_NAME"

**Cause**: Generic type is not available at runtime or doesn't conform to `Codable`.

**Example Error**:
```
RuntimeError.serializationFailed("Failed to resolve generic type from mangled name: Swift.Int")
```

**Common Causes**:

1. **Generic type doesn't conform to `Codable`**:
   ```swift
   // Wrong - Closure is not Codable!
   distributed func execute<T>(_ operation: () -> T) -> T
   ```

2. **Generic type not available in receiver process**:
   ```swift
   // Custom type only exists in sender process
   struct MyCustomType: Codable { ... }

   distributed func process<T: Codable>(_ value: T)
   ```

3. **Missing generic substitution recording**:
   ```swift
   // Wrong - forgot to record generic type!
   var encoder = CodableInvocationEncoder()
   // encoder.recordGenericSubstitution(Int.self)  // Forgot this!
   try encoder.recordValue(42)
   ```

**Solutions**:

1. **Ensure generic types conform to `Codable`**:
   ```swift
   // Correct - all generic parameters must be Codable
   distributed func store<T: Codable>(_ value: T, key: String)
   ```

2. **Use standard library types**:
   ```swift
   // Use built-in types that are available everywhere
   distributed func process(_ value: Int)  // ✅
   distributed func process(_ value: String)  // ✅
   distributed func process(_ value: [String: Int])  // ✅
   ```

3. **Share custom types across processes**:
   ```swift
   // Define custom type in shared module
   public struct Measurement: Codable, Sendable {
       let temperature: Double
       let timestamp: Date
   }

   // Both sender and receiver can use this type
   distributed func recordMeasurement(_ measurement: Measurement)
   ```

4. **Verify generic substitutions are recorded**:
   ```swift
   // Swift compiler does this automatically for distributed functions
   // Manual recording only needed for custom encoder usage
   var encoder = CodableInvocationEncoder()
   try encoder.recordGenericSubstitution(Int.self)
   try encoder.recordValue(42)
   ```

---

## Transport Errors

### Error: "Transport failed: CONNECTION_ERROR"

**Cause**: Network-level issues with the transport layer.

**Common Causes**:

1. **Network connectivity lost**
2. **Timeout waiting for response**
3. **Protocol-specific errors** (BLE disconnection, gRPC channel closed, etc.)

**Solutions**:

1. **Implement retry logic**:
   ```swift
   func remoteCallWithRetry<Res>(
       envelope: InvocationEnvelope,
       maxRetries: Int = 3
   ) async throws -> Res {
       var lastError: Error?

       for attempt in 1...maxRetries {
           do {
               return try await transport.sendInvocation(envelope)
           } catch {
               lastError = error
               if attempt < maxRetries {
                   try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
               }
           }
       }

       throw lastError!
   }
   ```

2. **Add timeout handling**:
   ```swift
   func sendWithTimeout<Res>(
       envelope: InvocationEnvelope,
       timeout: TimeInterval = 30.0
   ) async throws -> Res {
       try await withTimeout(timeout) {
           try await transport.sendInvocation(envelope)
       }
   }
   ```

3. **Check connection health**:
   ```swift
   guard transport.isConnected else {
       throw RuntimeError.transportFailed("Transport not connected")
   }
   ```

---

## Debugging Techniques

### 1. Enable Verbose Logging

Add logging to see what's happening:

```swift
// In your transport implementation
func handleInvocation(_ envelope: InvocationEnvelope) async throws {
    print("📥 Received invocation:")
    print("  - callID: \(envelope.callID)")
    print("  - recipientID: \(envelope.recipientID)")
    print("  - target: \(envelope.target)")
    print("  - arguments count: \(envelope.arguments.count) bytes")

    // ... handle invocation ...

    print("📤 Sending response for callID: \(envelope.callID)")
}
```

### 2. Inspect Serialized Data

Print the JSON representation of envelopes:

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted

let data = try encoder.encode(envelope)
if let json = String(data: data, encoding: .utf8) {
    print("📦 Envelope JSON:")
    print(json)
}
```

### 3. Verify Argument Encoding/Decoding

Test argument serialization in isolation:

```swift
// Test argument encoding
let testValue = "hello"
let encoded = try JSONEncoder().encode(testValue)
let decoded = try JSONDecoder().decode(String.self, from: encoded)
print("Round-trip: \(testValue) -> \(decoded)")
```

### 4. Add Distributed Tracing

Track requests across the distributed system:

```swift
let traceID = UUID().uuidString
let envelope = InvocationEnvelope(
    recipientID: actorID,
    target: method,
    arguments: args,
    metadata: .init(headers: ["trace-id": traceID])
)

print("🔍 Trace \(traceID): Sending invocation to \(actorID).\(method)")
```

### 5. Use Breakpoints Strategically

Set breakpoints at key points:

1. **Before sending invocation** (`remoteCall`)
2. **When receiving invocation** (server handler)
3. **In `executeDistributedTarget` call**
4. **When creating response** (`CodableResultHandler`)
5. **When receiving response** (client continuation)

### 6. Test with Mock Transport

Create a simple in-memory transport for testing:

```swift
actor InMemoryTransport {
    private var pendingResponses: [String: ResponseEnvelope] = [:]

    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        // Directly execute and return response
        let response = try await handleLocally(envelope)
        return response
    }
}
```

### 7. Verify Protocol Versions

Ensure both sides use the same protocol version:

```swift
guard envelope.metadata.version == expectedVersion else {
    print("⚠️ Version mismatch!")
    print("  Expected: \(expectedVersion)")
    print("  Received: \(envelope.metadata.version)")
    throw RuntimeError.versionMismatch(
        expected: expectedVersion,
        actual: envelope.metadata.version
    )
}
```

### 8. Monitor Execution Time

Track how long operations take:

```swift
let startTime = Date()
let response = try await handleInvocation(envelope)
let duration = Date().timeIntervalSince(startTime)

if duration > 1.0 {
    print("⚠️ Slow invocation: \(envelope.target) took \(duration)s")
}
```

### 9. Check Actor Registry State

Verify actors are registered correctly:

```swift
// Add debug method to ActorRegistry
func debugPrint() {
    mutex.withLock { state in
        print("🏪 Actor Registry:")
        print("  - Total actors: \(state.actors.count)")
        for (id, actor) in state.actors {
            print("  - \(id): \(type(of: actor))")
        }
    }
}
```

---

## Common Patterns to Avoid

### ❌ Don't: Forget to call `doneRecording()`

```swift
var encoder = CodableInvocationEncoder()
try encoder.recordValue(42)
// Forgot: try encoder.doneRecording()
let envelope = try encoder.makeInvocationEnvelope(...)  // Error!
```

### ✅ Do: Always call `doneRecording()`

```swift
var encoder = CodableInvocationEncoder()
try encoder.recordValue(42)
try encoder.doneRecording()  // ✅
let envelope = try encoder.makeInvocationEnvelope(...)
```

---

### ❌ Don't: Use closures in distributed methods

```swift
// Wrong - closures are not Codable!
distributed func execute(_ operation: () -> Void)
```

### ✅ Do: Use Codable data types

```swift
// Correct - use Codable types
distributed func execute(_ command: String)
```

---

### ❌ Don't: Forget to handle all response types

```swift
switch response.result {
case .success(let data):
    return try JSONDecoder().decode(Res.self, from: data)
// Missing .void and .failure cases!
}
```

### ✅ Do: Handle all cases

```swift
switch response.result {
case .success(let data):
    return try JSONDecoder().decode(Res.self, from: data)
case .void:
    return () as! Res
case .failure(let error):
    throw error
}
```

---

## Getting Help

If you're still stuck:

1. **Check the documentation**:
   - [DESIGN.md](DESIGN.md) - Architecture overview
   - [CODEC.md](CODEC.md) - Codec system details
   - [TRANSPORT_IMPLEMENTATION.md](TRANSPORT_IMPLEMENTATION.md) - Transport patterns

2. **Review example implementations**:
   - [Bleu](https://github.com/1amageek/Bleu) - BLE transport
   - [ActorEdge](https://github.com/1amageek/actor-edge) - gRPC transport

3. **File an issue**:
   - Include relevant code snippets
   - Provide error messages
   - Describe what you've already tried

4. **Enable debug logging** and share the output
