import Testing
import Foundation
import Synchronization
@testable import ActorRuntime

/// Mock transport implementation for testing
final class MockTransport: DistributedTransport, Sendable {

    private struct State: Sendable {
        var isStarted = false
        var isStopped = false
        var sentEnvelopes: [Envelope] = []
    }

    private let state = Mutex(State())
    private let continuationHolder = Mutex<AsyncThrowingStream<Envelope, Error>.Continuation?>(nil)
    private let streamHolder = Mutex<AsyncThrowingStream<Envelope, Error>?>(nil)

    var isStarted: Bool {
        state.withLock { $0.isStarted }
    }

    var isStopped: Bool {
        state.withLock { $0.isStopped }
    }

    var sentEnvelopes: [Envelope] {
        state.withLock { $0.sentEnvelopes }
    }

    var messages: AsyncThrowingStream<Envelope, Error> {
        streamHolder.withLock { existingStream in
            if let existing = existingStream {
                return existing
            }
            let stream = AsyncThrowingStream<Envelope, Error> { continuation in
                self.continuationHolder.withLock { $0 = continuation }
            }
            existingStream = stream
            return stream
        }
    }

    func start() async throws {
        state.withLock { $0.isStarted = true }
    }

    func send(_ envelope: Envelope) async throws {
        try state.withLock { state in
            guard state.isStarted && !state.isStopped else {
                throw RuntimeError.transportFailed("Transport not running")
            }
            state.sentEnvelopes.append(envelope)
        }
    }

    func stop() async {
        state.withLock { $0.isStopped = true }
        continuationHolder.withLock { $0?.finish() }
    }

    /// Simulate receiving an envelope from remote peer
    func simulateReceive(_ envelope: Envelope) {
        continuationHolder.withLock { cont in
            _ = cont?.yield(envelope)
        }
    }

    /// Simulate a transport error
    func simulateError(_ error: Error) {
        continuationHolder.withLock { $0?.finish(throwing: error) }
    }
}

@Suite("DistributedTransport Protocol Tests")
struct TransportProtocolTests {

    @Test("Transport lifecycle: start and stop")
    func testTransportLifecycle() async throws {
        let transport = MockTransport()

        #expect(!transport.isStarted)
        #expect(!transport.isStopped)

        try await transport.start()

        #expect(transport.isStarted)
        #expect(!transport.isStopped)

        await transport.stop()

        #expect(transport.isStarted)
        #expect(transport.isStopped)
    }

    @Test("Transport send invocation envelope")
    func testTransportSendInvocation() async throws {
        let transport = MockTransport()
        try await transport.start()

        let invocation = InvocationEnvelope(
            callID: "call-123",
            recipientID: "sensor-1",
            target: "readTemperature",
            arguments: Data([1, 2, 3])
        )

        try await transport.send(.invocation(invocation))

        #expect(transport.sentEnvelopes.count == 1)

        switch transport.sentEnvelopes[0] {
        case .invocation(let inv):
            #expect(inv.callID == "call-123")
            #expect(inv.recipientID == "sensor-1")
        case .response:
            Issue.record("Expected invocation")
        }
    }

    @Test("Transport send response envelope")
    func testTransportSendResponse() async throws {
        let transport = MockTransport()
        try await transport.start()

        let response = ResponseEnvelope(
            callID: "call-123",
            result: .success(Data([42]))
        )

        try await transport.send(.response(response))

        #expect(transport.sentEnvelopes.count == 1)

        switch transport.sentEnvelopes[0] {
        case .response(let res):
            #expect(res.callID == "call-123")
        case .invocation:
            Issue.record("Expected response")
        }
    }

    @Test("Transport send multiple envelopes")
    func testTransportSendMultiple() async throws {
        let transport = MockTransport()
        try await transport.start()

        let invocation = InvocationEnvelope(
            callID: "call-1",
            recipientID: "actor-1",
            target: "method1",
            arguments: Data()
        )

        let response = ResponseEnvelope(
            callID: "call-1",
            result: .void
        )

        try await transport.send(.invocation(invocation))
        try await transport.send(.response(response))

        #expect(transport.sentEnvelopes.count == 2)

        switch transport.sentEnvelopes[0] {
        case .invocation: break
        case .response: Issue.record("Expected invocation first")
        }

        switch transport.sentEnvelopes[1] {
        case .response: break
        case .invocation: Issue.record("Expected response second")
        }
    }

    @Test("Transport receive messages via stream")
    func testTransportReceiveMessages() async throws {
        let transport = MockTransport()
        try await transport.start()

        // Access messages to initialize the stream
        let _ = transport.messages

        // Simulate receiving messages
        let invocation = InvocationEnvelope(
            callID: "call-1",
            recipientID: "actor-1",
            target: "method1",
            arguments: Data()
        )

        let response = ResponseEnvelope(
            callID: "call-1",
            result: .success(Data([42]))
        )

        // Start collecting in background
        let received = Task {
            var envelopes: [Envelope] = []
            for try await envelope in transport.messages {
                envelopes.append(envelope)
                if envelopes.count == 2 {
                    break
                }
            }
            return envelopes
        }

        // Give time for the stream to be ready
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        transport.simulateReceive(.invocation(invocation))
        transport.simulateReceive(.response(response))

        let envelopes = try await received.value

        #expect(envelopes.count == 2)

        switch envelopes[0] {
        case .invocation(let inv):
            #expect(inv.callID == "call-1")
        case .response:
            Issue.record("Expected invocation")
        }

        switch envelopes[1] {
        case .response(let res):
            #expect(res.callID == "call-1")
        case .invocation:
            Issue.record("Expected response")
        }
    }

    @Test("Transport fails to send when not started")
    func testTransportSendBeforeStart() async throws {
        let transport = MockTransport()

        let invocation = InvocationEnvelope(
            callID: "call-1",
            recipientID: "actor-1",
            target: "method1",
            arguments: Data()
        )

        await #expect(throws: RuntimeError.self) {
            try await transport.send(.invocation(invocation))
        }
    }

    @Test("Transport fails to send after stop")
    func testTransportSendAfterStop() async throws {
        let transport = MockTransport()
        try await transport.start()
        await transport.stop()

        let invocation = InvocationEnvelope(
            callID: "call-1",
            recipientID: "actor-1",
            target: "method1",
            arguments: Data()
        )

        await #expect(throws: RuntimeError.self) {
            try await transport.send(.invocation(invocation))
        }
    }

    @Test("Transport bidirectional communication pattern")
    func testBidirectionalCommunication() async throws {
        let transport = MockTransport()
        try await transport.start()

        // Simulate a request-response cycle
        // 1. Send invocation
        let invocation = InvocationEnvelope(
            callID: "call-123",
            recipientID: "sensor-1",
            senderID: "client-1",
            target: "readTemperature",
            arguments: Data()
        )
        try await transport.send(.invocation(invocation))

        // 2. Simulate receiving response
        let _ = transport.messages

        let responseTask = Task<Envelope?, Error> {
            for try await envelope in transport.messages {
                return envelope
            }
            return nil
        }

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let response = ResponseEnvelope(
            callID: "call-123",
            result: .success(Data([42])),
            metadata: .init(executionTime: 0.05)
        )
        transport.simulateReceive(.response(response))

        let received = try await responseTask.value

        // Verify the cycle
        #expect(transport.sentEnvelopes.count == 1)
        #expect(received != nil)

        if case .response(let res) = received {
            #expect(res.callID == invocation.callID)
            #expect(res.metadata.executionTime == 0.05)
        } else {
            Issue.record("Expected response envelope")
        }
    }
}
