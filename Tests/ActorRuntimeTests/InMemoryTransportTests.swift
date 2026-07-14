import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Distributed
import Synchronization
@testable import ActorRuntime

// Include the InMemoryActorSystem implementation inline for testing
#if canImport(Distributed)

final class InMemoryActorSystem: DistributedActorSystem, Sendable {
    typealias ActorID = String
    typealias InvocationEncoder = CodableInvocationEncoder
    typealias InvocationDecoder = CodableInvocationDecoder
    typealias SerializationRequirement = Codable
    typealias ResultHandler = CodableResultHandler

    private let registry = ActorRegistry()
    private let idState = Mutex(0)

    init() {}

    func assignID<Act>(_ actorType: Act.Type) -> ActorID where Act: DistributedActor {
        idState.withLock { nextID in
            let id = "\(actorType)-\(nextID)"
            nextID += 1
            return id
        }
    }

    func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {
        registry.register(actor, id: actor.id)
    }

    func resignID(_ id: ActorID) {
        registry.unregister(id: id)
    }

    func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable {
        invocation.recordTarget(target)
        let envelope = try invocation.makeInvocationEnvelope(recipientID: actor.id)

        guard let targetActor = registry.find(id: envelope.recipientID) else {
            throw RuntimeError.actorNotFound(envelope.recipientID)
        }

        var decoder = try CodableInvocationDecoder(envelope: envelope)
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

        try await executeDistributedTarget(
            on: targetActor,
            target: target,
            invocationDecoder: &decoder,
            handler: handler
        )

        guard let result = capturedResult else {
            throw RuntimeError.executionFailed("No result captured", underlying: "Unknown")
        }

        return try result.get()
    }

    func remoteCallVoid<Act, Err>(
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

    func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID
    {
        return registry.find(id: id) as? Act
    }

    func makeInvocationEncoder() -> InvocationEncoder {
        return CodableInvocationEncoder()
    }

    deinit {
        registry.clear()
    }
}

// Test actors
distributed actor Counter {
    typealias ActorSystem = InMemoryActorSystem

    private var value: Int = 0

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    distributed func increment() -> Int {
        value += 1
        return value
    }

    distributed func add(_ amount: Int) -> Int {
        value += amount
        return value
    }

    distributed func getValue() -> Int {
        return value
    }

    distributed func reset() {
        value = 0
    }
}

distributed actor DataStore {
    typealias ActorSystem = InMemoryActorSystem

    struct Record: Codable, Sendable {
        let id: String
        let data: [String: String]

        init(id: String, data: [String: String]) {
            self.id = id
            self.data = data
        }
    }

    private var records: [String: Record] = [:]

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    distributed func store(_ record: Record) {
        records[record.id] = record
    }

    distributed func fetch(_ id: String) -> Record? {
        return records[id]
    }

    distributed func list() -> [Record] {
        return Array(records.values)
    }
}

// Generic distributed actor
distributed actor GenericContainer<T: Codable & Sendable> {
    typealias ActorSystem = InMemoryActorSystem

    private var value: T

    init(initialValue: T, actorSystem: ActorSystem) {
        self.value = initialValue
        self.actorSystem = actorSystem
    }

    distributed func getValue() -> T {
        return value
    }

    distributed func setValue(_ newValue: T) {
        self.value = newValue
    }
}

@Suite("InMemory Transport Integration Tests")
struct InMemoryTransportTests {

    @Test("Counter: basic increment")
    func counterBasicIncrement() async throws {
        let system = InMemoryActorSystem()
        let counter = Counter(actorSystem: system)

        let result1 = try await counter.increment()
        #expect(result1 == 1)

        let result2 = try await counter.increment()
        #expect(result2 == 2)

        let current = try await counter.getValue()
        #expect(current == 2)
    }

    @Test("Counter: add with argument")
    func counterAddWithArgument() async throws {
        let system = InMemoryActorSystem()
        let counter = Counter(actorSystem: system)

        let result1 = try await counter.add(5)
        #expect(result1 == 5)

        let result2 = try await counter.add(10)
        #expect(result2 == 15)

        let current = try await counter.getValue()
        #expect(current == 15)
    }

    @Test("Counter: reset void method")
    func counterResetVoidMethod() async throws {
        let system = InMemoryActorSystem()
        let counter = Counter(actorSystem: system)

        _ = try await counter.add(42)
        let before = try await counter.getValue()
        #expect(before == 42)

        try await counter.reset()

        let after = try await counter.getValue()
        #expect(after == 0)
    }

    @Test("DataStore: store and fetch complex types")
    func dataStoreStoreAndFetch() async throws {
        let system = InMemoryActorSystem()
        let store = DataStore(actorSystem: system)

        let record = DataStore.Record(
            id: "test-1",
            data: ["key1": "value1", "key2": "value2"]
        )

        try await store.store(record)

        let fetched = try await store.fetch("test-1")
        #expect(fetched != nil)
        #expect(fetched?.id == "test-1")
        #expect(fetched?.data["key1"] == "value1")
    }

    @Test("DataStore: fetch non-existent returns nil")
    func dataStoreFetchNonExistent() async throws {
        let system = InMemoryActorSystem()
        let store = DataStore(actorSystem: system)

        let result = try await store.fetch("does-not-exist")
        #expect(result == nil)
    }

    @Test("DataStore: list multiple records")
    func dataStoreListMultipleRecords() async throws {
        let system = InMemoryActorSystem()
        let store = DataStore(actorSystem: system)

        let record1 = DataStore.Record(id: "1", data: ["a": "b"])
        let record2 = DataStore.Record(id: "2", data: ["c": "d"])
        let record3 = DataStore.Record(id: "3", data: ["e": "f"])

        try await store.store(record1)
        try await store.store(record2)
        try await store.store(record3)

        let list = try await store.list()
        #expect(list.count == 3)

        let ids = Set(list.map { $0.id })
        #expect(ids.contains("1"))
        #expect(ids.contains("2"))
        #expect(ids.contains("3"))
    }

    @Test("Multiple actors in same system")
    func multipleActorsInSameSystem() async throws {
        let system = InMemoryActorSystem()

        let counter1 = Counter(actorSystem: system)
        let counter2 = Counter(actorSystem: system)

        _ = try await counter1.add(10)
        _ = try await counter2.add(20)

        let value1 = try await counter1.getValue()
        let value2 = try await counter2.getValue()

        #expect(value1 == 10)
        #expect(value2 == 20)
    }

    @Test("Actor not found error")
    func actorNotFoundError() async throws {
        let system = InMemoryActorSystem()

        // Try to resolve non-existent actor
        let resolved = try system.resolve(id: "non-existent", as: Counter.self)
        #expect(resolved == nil)
    }

    @Test("Generic container with Int")
    func genericContainerWithInt() async throws {
        let system = InMemoryActorSystem()
        let container = GenericContainer(initialValue: 42, actorSystem: system)

        let value = try await container.getValue()
        #expect(value == 42)

        try await container.setValue(100)
        let newValue = try await container.getValue()
        #expect(newValue == 100)
    }

    @Test("Generic container with String")
    func genericContainerWithString() async throws {
        let system = InMemoryActorSystem()
        let container = GenericContainer(initialValue: "hello", actorSystem: system)

        let value = try await container.getValue()
        #expect(value == "hello")

        try await container.setValue("world")
        let newValue = try await container.getValue()
        #expect(newValue == "world")
    }

    @Test("Generic container with custom struct")
    func genericContainerWithCustomStruct() async throws {
        struct Person: Codable, Sendable, Equatable {
            let name: String
            let age: Int
        }

        let system = InMemoryActorSystem()
        let person = Person(name: "Alice", age: 30)
        let container = GenericContainer(initialValue: person, actorSystem: system)

        let value = try await container.getValue()
        #expect(value == person)

        let newPerson = Person(name: "Bob", age: 25)
        try await container.setValue(newPerson)
        let newValue = try await container.getValue()
        #expect(newValue == newPerson)
    }

}

#endif
