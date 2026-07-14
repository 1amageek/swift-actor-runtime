import Distributed
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActorRuntime
import Synchronization

/// A simple in-memory transport for testing and demonstration purposes.
///
/// This implementation shows how to use the Codec system to enable
/// distributed method calls without an actual network transport.
///
/// ## Example Usage
///
/// ```swift
/// // Define a distributed actor
/// distributed actor Counter {
///     typealias ActorSystem = InMemoryActorSystem
///
///     private var value: Int = 0
///
///     distributed func increment() -> Int {
///         value += 1
///         return value
///     }
///
///     distributed func getValue() -> Int {
///         return value
///     }
/// }
///
/// // Create actor system
/// let system = InMemoryActorSystem()
///
/// // Create local actor
/// let counter = Counter(actorSystem: system)
///
/// // Call methods (locally)
/// let result1 = try await counter.increment() // 1
/// let result2 = try await counter.increment() // 2
/// let current = try await counter.getValue()  // 2
/// ```
public final class InMemoryActorSystem: DistributedActorSystem, Sendable {
    public typealias ActorID = String
    public typealias InvocationEncoder = CodableInvocationEncoder
    public typealias InvocationDecoder = CodableInvocationDecoder
    public typealias SerializationRequirement = Codable
    public typealias ResultHandler = CodableResultHandler

    private let registry = ActorRegistry()
    private let idState = Mutex(0)

    public init() {}

    // MARK: - ActorID Generation

    public func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
        idState.withLock { nextID in
            let id = "\(actorType)-\(nextID)"
            nextID += 1
            return id
        }
    }

    // MARK: - Actor Lifecycle

    public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {
        registry.register(actor, id: actor.id)
    }

    public func resignID(_ id: ActorID) {
        registry.unregister(id: id)
    }

    // MARK: - Remote Calls

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable {
        // Record the target
        invocation.recordTarget(target)

        // Create envelope
        let envelope = try invocation.makeInvocationEnvelope(
            recipientID: actor.id
        )

        // For in-memory transport, we directly execute locally
        // In a real transport, this would be sent over the network

        // Find the actor
        guard let targetActor = registry.find(id: envelope.recipientID) else {
            throw RuntimeError.actorNotFound(envelope.recipientID)
        }

        // Create decoder
        var decoder = try CodableInvocationDecoder(envelope: envelope)

        // Create result handler
        var capturedResult: Result<Res, Error>?
        let handler = CodableResultHandler(callID: envelope.callID) { response in
            switch response.result {
            case .success(let data):
                let value = try JSONDecoder().decode(Res.self, from: data)
                capturedResult = .success(value)
            case .void:
                capturedResult = .success(() as! Res)
            case .failure(let error):
                capturedResult = .failure(error)
            }
        }

        // Execute the method
        try await executeDistributedTarget(
            on: targetActor,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
        )

        // Return the result
        guard let result = capturedResult else {
            throw RuntimeError.executionFailed("No result captured", underlying: "Unknown")
        }

        return try result.get()
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws where Act: DistributedActor, Act.ID == ActorID, Err: Error {
        invocation.recordTarget(target)
        let envelope = try invocation.makeInvocationEnvelope(recipientID: actor.id)

        guard let targetActor = registry.find(id: envelope.recipientID) else {
            throw RuntimeError.actorNotFound(envelope.recipientID)
        }

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        var completed = false

        let handler = CodableResultHandler(callID: envelope.callID) { response in
            switch response.result {
            case .void:
                completed = true
            case .failure(let error):
                throw error
            default:
                throw RuntimeError.executionFailed("Expected void result", underlying: "Type mismatch")
            }
        }

        try await executeDistributedTarget(
            on: targetActor,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
        )

        guard completed else {
            throw RuntimeError.executionFailed("Void call did not complete", underlying: "Unknown")
        }
    }

    // MARK: - Actor Resolution

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        return registry.find(id: id) as? Act
    }

    public func makeInvocationEncoder() -> InvocationEncoder {
        return CodableInvocationEncoder()
    }

    // MARK: - Cleanup

    deinit {
        registry.clear()
    }
}

// MARK: - Example Usage

#if DEBUG
/// Example distributed actor for demonstration
public distributed actor Counter {
    public typealias ActorSystem = InMemoryActorSystem

    private var value: Int = 0

    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    public distributed func increment() -> Int {
        value += 1
        return value
    }

    public distributed func add(_ amount: Int) -> Int {
        value += amount
        return value
    }

    public distributed func getValue() -> Int {
        return value
    }

    public distributed func reset() {
        value = 0
    }
}

/// Example distributed actor with complex types
public distributed actor DataStore {
    public typealias ActorSystem = InMemoryActorSystem

    public struct Record: Codable, Sendable {
        public let id: String
        public let data: [String: String]
        public let timestamp: Date

        public init(id: String, data: [String: String], timestamp: Date = Date()) {
            self.id = id
            self.data = data
            self.timestamp = timestamp
        }
    }

    private var records: [String: Record] = [:]

    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    public distributed func store(_ record: Record) {
        records[record.id] = record
    }

    public distributed func fetch(_ id: String) -> Record? {
        return records[id]
    }

    public distributed func list() -> [Record] {
        return Array(records.values)
    }

    public distributed func delete(_ id: String) -> Bool {
        return records.removeValue(forKey: id) != nil
    }
}

/// Example generic distributed actor
public distributed actor GenericContainer<T: Codable & Sendable> {
    public typealias ActorSystem = InMemoryActorSystem

    private var value: T

    public init(initialValue: T, actorSystem: ActorSystem) {
        self.value = initialValue
        self.actorSystem = actorSystem
    }

    public distributed func getValue() -> T {
        return value
    }

    public distributed func setValue(_ newValue: T) {
        self.value = newValue
    }
}
#endif
