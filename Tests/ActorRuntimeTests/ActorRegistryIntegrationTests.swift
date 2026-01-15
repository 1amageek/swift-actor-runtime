import Testing
import Foundation
import Distributed
import Synchronization
@testable import ActorRuntime

// MARK: - Mock ActorSystem for Testing

/// Minimal DistributedActorSystem implementation for testing ActorRegistry
final class MockActorSystem: DistributedActorSystem, @unchecked Sendable {
    typealias ActorID = String
    typealias InvocationEncoder = MockInvocationEncoder
    typealias InvocationDecoder = MockInvocationDecoder
    typealias SerializationRequirement = Codable
    typealias ResultHandler = MockResultHandler

    private let registry = ActorRegistry()

    func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act: DistributedActor {
        registry.find(id: id) as? Act
    }

    func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
        UUID().uuidString
    }

    func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
        registry.register(actor, id: actor.id as! String)
    }

    func resignID(_ id: ActorID) {
        registry.unregister(id: id)
    }

    func makeInvocationEncoder() -> InvocationEncoder {
        MockInvocationEncoder()
    }

    nonisolated func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: SerializationRequirement {
        fatalError("Remote call not implemented in mock")
    }

    nonisolated func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {
        fatalError("Remote call void not implemented in mock")
    }

    func invokeHandlerOnReturn(
        handler: ResultHandler,
        resultBuffer: UnsafeRawPointer,
        metatype: Any.Type
    ) async throws {
        // Mock implementation for testing
        // In a real distributed actor system, this would:
        // 1. Deserialize the value from resultBuffer using metatype
        // 2. Call handler.onReturn(value:) with the typed value
        // For testing purposes, we just call onReturnVoid()
        try await handler.onReturnVoid()
    }

    // Internal accessor for testing
    var testRegistry: ActorRegistry { registry }
}

struct MockInvocationEncoder: DistributedTargetInvocationEncoder {
    typealias SerializationRequirement = Codable

    mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {}
    mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {}
    mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {}
    mutating func recordErrorType<E: Error>(_ type: E.Type) throws {}
    mutating func doneRecording() throws {}
}

struct MockInvocationDecoder: DistributedTargetInvocationDecoder {
    typealias SerializationRequirement = Codable

    mutating func decodeGenericSubstitutions() throws -> [Any.Type] { [] }
    mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        fatalError("Decode not implemented in mock")
    }
    mutating func decodeReturnType() throws -> Any.Type? { nil }
    mutating func decodeErrorType() throws -> Any.Type? { nil }
}

struct MockResultHandler: DistributedTargetInvocationResultHandler {
    typealias SerializationRequirement = Codable

    func onReturn<Success: Codable>(value: Success) async throws {}
    func onReturnVoid() async throws {}
    func onThrow<Failure: Error>(error: Failure) async throws {}
}

// MARK: - Test Distributed Actors

distributed actor TestSensor {
    typealias ActorSystem = MockActorSystem

    var temperature: Double = 22.5

    distributed func readTemperature() -> Double {
        temperature
    }

    distributed func updateTemperature(_ value: Double) {
        temperature = value
    }
}

distributed actor TestDevice {
    typealias ActorSystem = MockActorSystem

    let deviceName: String

    init(name: String, actorSystem: MockActorSystem) {
        self.deviceName = name
        self.actorSystem = actorSystem
    }

    distributed func getName() -> String {
        deviceName
    }
}

// MARK: - Integration Tests

@Suite("ActorRegistry Integration Tests")
struct ActorRegistryIntegrationTests {

    @Test("ActorRegistry register and find real distributed actor")
    func testRegisterAndFindRealActor() async throws {
        let system = MockActorSystem()
        let sensor = TestSensor(actorSystem: system)
        let actorID = sensor.id

        // Actor should be automatically registered via actorReady
        let found = system.testRegistry.find(id: actorID)
        #expect(found != nil)

        // Verify it's the same actor by checking type
        #expect(found is TestSensor)
    }

    @Test("ActorRegistry full lifecycle: register, find, unregister")
    func testFullLifecycle() async throws {
        let system = MockActorSystem()
        let sensor = TestSensor(actorSystem: system)
        let actorID = sensor.id

        // Step 1: Verify actor is registered
        #expect(system.testRegistry.count == 1)
        let found = system.testRegistry.find(id: actorID)
        #expect(found != nil)

        // Step 2: Unregister the actor
        system.testRegistry.unregister(id: actorID)

        // Step 3: Verify actor is no longer found
        #expect(system.testRegistry.count == 0)
        let notFound = system.testRegistry.find(id: actorID)
        #expect(notFound == nil)
    }

    @Test("ActorRegistry register multiple actors")
    func testMultipleActors() async throws {
        let system = MockActorSystem()

        let sensor1 = TestSensor(actorSystem: system)
        let sensor2 = TestSensor(actorSystem: system)
        let device = TestDevice(name: "Device1", actorSystem: system)

        // Verify all three actors are registered
        #expect(system.testRegistry.count == 3)

        let allIDs = system.testRegistry.allActorIDs()
        #expect(allIDs.count == 3)
        #expect(allIDs.contains(sensor1.id))
        #expect(allIDs.contains(sensor2.id))
        #expect(allIDs.contains(device.id))
    }

    @Test("ActorRegistry find by ID returns correct actor")
    func testFindByIDReturnsCorrectActor() async throws {
        let system = MockActorSystem()

        let device1 = TestDevice(name: "Device1", actorSystem: system)
        let device2 = TestDevice(name: "Device2", actorSystem: system)

        let device1ID = device1.id
        let device2ID = device2.id

        // Find device1
        let found1 = system.testRegistry.find(id: device1ID)
        #expect(found1 != nil)
        #expect(found1 is TestDevice)

        // Find device2
        let found2 = system.testRegistry.find(id: device2ID)
        #expect(found2 != nil)
        #expect(found2 is TestDevice)

        // Verify they are different actors
        #expect(device1ID != device2ID)
    }

    @Test("ActorRegistry clear removes all actors")
    func testClearRemovesAllActors() async throws {
        let system = MockActorSystem()

        _ = TestSensor(actorSystem: system)
        _ = TestSensor(actorSystem: system)
        _ = TestDevice(name: "Device", actorSystem: system)

        #expect(system.testRegistry.count == 3)

        system.testRegistry.clear()

        #expect(system.testRegistry.count == 0)
        #expect(system.testRegistry.allActorIDs().isEmpty)
    }

    @Test("ActorRegistry concurrent registration and lookup")
    func testConcurrentRegistrationAndLookup() async throws {
        let system = MockActorSystem()

        // Create multiple actors concurrently
        await withTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let sensor = TestSensor(actorSystem: system)
                    return sensor.id
                }
            }

            // Collect all IDs
            var actorIDs: [String] = []
            for await id in group {
                actorIDs.append(id)
            }

            // Verify all actors were registered
            #expect(system.testRegistry.count == 10)

            // Verify all can be found
            for id in actorIDs {
                let found = system.testRegistry.find(id: id)
                #expect(found != nil)
            }
        }
    }

    @Test("ActorRegistry overwrite on duplicate ID registration")
    func testOverwriteOnDuplicateID() async throws {
        let system = MockActorSystem()
        let registry = system.testRegistry

        let sensor1 = TestSensor(actorSystem: system)
        let id1 = sensor1.id

        // Manually register another sensor with the same ID (simulating edge case)
        let sensor2 = TestSensor(actorSystem: system)
        registry.register(sensor2, id: id1)  // Overwrites sensor1

        // Should still have only one entry for id1 (overwritten), plus sensor2's original ID
        #expect(registry.count == 2)  // sensor1's ID + sensor2's ID

        // Find by id1 should return the last registered actor
        let found = registry.find(id: id1)
        #expect(found != nil)
    }

    @Test("ActorRegistry resignID removes actor")
    func testResignIDRemovesActor() async throws {
        let system = MockActorSystem()
        let sensor = TestSensor(actorSystem: system)
        let actorID = sensor.id

        #expect(system.testRegistry.count == 1)

        // Call resignID (simulates actor cleanup)
        system.resignID(actorID)

        #expect(system.testRegistry.count == 0)
        #expect(system.testRegistry.find(id: actorID) == nil)
    }

    // MARK: - Recursive Lock Prevention Tests
    //
    // These tests verify that ActorRegistry doesn't deadlock when actor deinit
    // calls resignID() during unregister() or clear() operations.
    // The fix uses withExtendedLifetime to ensure actors are released outside the lock.

    @Test("ActorRegistry unregister does not deadlock on deinit resignID", .timeLimit(.minutes(1)))
    func testUnregisterNoDeadlockOnDeinitResignID() async throws {
        let system = RecursiveLockTestSystem()

        // Create actor - system is the only strong reference holder via registry
        let actorID: String
        do {
            let actor = RecursiveLockTestActor(actorSystem: system)
            actorID = actor.id
        }
        // actor variable goes out of scope, but registry still holds reference

        #expect(system.testRegistry.count == 1)

        // This should NOT deadlock even though the actor's deinit will call resignID
        // because the actor is released outside the lock
        system.testRegistry.unregister(id: actorID)

        // If we reach here, no deadlock occurred
        #expect(system.testRegistry.count == 0)
        #expect(system.resignIDCallCount == 1, "resignID should have been called once during unregister")
    }

    @Test("ActorRegistry clear does not deadlock on multiple deinit resignID", .timeLimit(.minutes(1)))
    func testClearNoDeadlockOnMultipleDeinitResignID() async throws {
        let system = RecursiveLockTestSystem()

        // Create multiple actors
        for _ in 0..<5 {
            _ = RecursiveLockTestActor(actorSystem: system)
        }

        #expect(system.testRegistry.count == 5)

        // This should NOT deadlock even though all actors' deinit will call resignID
        system.testRegistry.clear()

        // If we reach here, no deadlock occurred
        #expect(system.testRegistry.count == 0)
        #expect(system.resignIDCallCount == 5, "resignID should have been called 5 times during clear")
    }

    @Test("ActorRegistry handles rapid register-unregister cycles without deadlock", .timeLimit(.minutes(1)))
    func testRapidRegisterUnregisterCycles() async throws {
        let system = RecursiveLockTestSystem()

        // Rapidly create and unregister actors
        for _ in 0..<20 {
            let actor = RecursiveLockTestActor(actorSystem: system)
            let actorID = actor.id

            // Immediately unregister
            system.testRegistry.unregister(id: actorID)

            // Verify cleanup
            #expect(system.testRegistry.find(id: actorID) == nil)
        }

        #expect(system.testRegistry.count == 0)
        // Each actor's deinit should have called resignID
        #expect(system.resignIDCallCount == 20)
    }

    @Test("ActorRegistry concurrent unregister does not deadlock", .timeLimit(.minutes(1)))
    func testConcurrentUnregisterNoDeadlock() async throws {
        let system = RecursiveLockTestSystem()

        // Create actors
        var actorIDs: [String] = []
        for _ in 0..<10 {
            let actor = RecursiveLockTestActor(actorSystem: system)
            actorIDs.append(actor.id)
        }

        #expect(system.testRegistry.count == 10)

        // Concurrently unregister all actors
        await withTaskGroup(of: Void.self) { group in
            for id in actorIDs {
                group.addTask {
                    system.testRegistry.unregister(id: id)
                }
            }
        }

        // If we reach here, no deadlock occurred
        #expect(system.testRegistry.count == 0)
    }
}

// MARK: - Recursive Lock Test Infrastructure

/// ActorSystem that tracks resignID calls to verify deinit behavior
final class RecursiveLockTestSystem: DistributedActorSystem, @unchecked Sendable {
    typealias ActorID = String
    typealias InvocationEncoder = MockInvocationEncoder
    typealias InvocationDecoder = MockInvocationDecoder
    typealias SerializationRequirement = Codable
    typealias ResultHandler = MockResultHandler

    let testRegistry = ActorRegistry()
    private let _resignIDCallCount = Mutex<Int>(0)

    var resignIDCallCount: Int {
        _resignIDCallCount.withLock { $0 }
    }

    func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? where Act: DistributedActor {
        testRegistry.find(id: id) as? Act
    }

    func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
        UUID().uuidString
    }

    func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
        testRegistry.register(actor, id: actor.id as! String)
    }

    func resignID(_ id: ActorID) {
        _resignIDCallCount.withLock { $0 += 1 }
        // This simulates what happens when actor deinit calls resignID
        // If the lock isn't properly released before deinit, this will deadlock
        testRegistry.unregister(id: id)
    }

    func makeInvocationEncoder() -> InvocationEncoder {
        MockInvocationEncoder()
    }

    nonisolated func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: SerializationRequirement {
        fatalError("Remote call not implemented")
    }

    nonisolated func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {
        fatalError("Remote call void not implemented")
    }

    func invokeHandlerOnReturn(
        handler: ResultHandler,
        resultBuffer: UnsafeRawPointer,
        metatype: Any.Type
    ) async throws {
        try await handler.onReturnVoid()
    }
}

/// Test actor that triggers resignID on deinit
distributed actor RecursiveLockTestActor {
    typealias ActorSystem = RecursiveLockTestSystem

    distributed func ping() -> String {
        "pong"
    }
}
