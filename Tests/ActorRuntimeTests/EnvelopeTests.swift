import Testing
import Foundation
@testable import ActorRuntime

@Suite("Envelope Tests")
struct EnvelopeTests {

    @Test("InvocationEnvelope creation and encoding")
    func testInvocationEnvelopeCreation() throws {
        let envelope = InvocationEnvelope(
            recipientID: "sensor-1",
            senderID: "client-1",
            target: "readTemperature",
            arguments: Data([1, 2, 3])
        )

        #expect(envelope.recipientID == "sensor-1")
        #expect(envelope.senderID == "client-1")
        #expect(envelope.target == "readTemperature")
        #expect(envelope.arguments == Data([1, 2, 3]))
        #expect(envelope.metadata.version == "1.0")
        #expect(!envelope.callID.isEmpty)
    }

    @Test("InvocationEnvelope encoding and decoding")
    func testInvocationEnvelopeEncodingDecoding() throws {
        let original = InvocationEnvelope(
            callID: "test-call-123",
            recipientID: "sensor-1",
            senderID: "client-1",
            target: "readTemperature",
            arguments: Data([1, 2, 3]),
            metadata: .init(
                timestamp: Date(timeIntervalSince1970: 1000),
                version: "1.0",
                headers: ["key": "value"]
            )
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(InvocationEnvelope.self, from: data)

        #expect(decoded.callID == original.callID)
        #expect(decoded.recipientID == original.recipientID)
        #expect(decoded.senderID == original.senderID)
        #expect(decoded.target == original.target)
        #expect(decoded.arguments == original.arguments)
        #expect(decoded.metadata.version == original.metadata.version)
        #expect(decoded.metadata.headers == original.metadata.headers)
    }

    @Test("ResponseEnvelope with success result")
    func testResponseEnvelopeSuccess() throws {
        let resultData = Data([42])
        let envelope = ResponseEnvelope(
            callID: "test-call-123",
            result: .success(resultData)
        )

        #expect(envelope.callID == "test-call-123")

        switch envelope.result {
        case .success(let data):
            #expect(data == resultData)
        default:
            Issue.record("Expected success result")
        }
    }

    @Test("ResponseEnvelope with void result")
    func testResponseEnvelopeVoid() throws {
        let envelope = ResponseEnvelope(
            callID: "test-call-123",
            result: .void
        )

        switch envelope.result {
        case .void:
            break // Success
        default:
            Issue.record("Expected void result")
        }
    }

    @Test("ResponseEnvelope with failure result")
    func testResponseEnvelopeFailure() throws {
        let error = RuntimeError.methodNotFound("readTemperature")
        let envelope = ResponseEnvelope(
            callID: "test-call-123",
            result: .failure(error)
        )

        switch envelope.result {
        case .failure(let receivedError):
            #expect(receivedError == error)
        default:
            Issue.record("Expected failure result")
        }
    }

    @Test("ResponseEnvelope encoding and decoding")
    func testResponseEnvelopeEncodingDecoding() throws {
        let testCases: [InvocationResult] = [
            .success(Data([1, 2, 3])),
            .void,
            .failure(.actorNotFound("sensor-1"))
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for result in testCases {
            let original = ResponseEnvelope(
                callID: "test-call",
                result: result,
                metadata: .init(
                    timestamp: Date(timeIntervalSince1970: 1000),
                    executionTime: 0.5,
                    headers: ["trace": "123"]
                )
            )

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(ResponseEnvelope.self, from: data)

            #expect(decoded.callID == original.callID)
            #expect(decoded.result == original.result)
            #expect(decoded.metadata.executionTime == original.metadata.executionTime)
            #expect(decoded.metadata.headers == original.metadata.headers)
        }
    }

    @Test("InvocationResult encoding and decoding")
    func testInvocationResultEncodingDecoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Success case
        let successResult = InvocationResult.success(Data([1, 2, 3]))
        let successData = try encoder.encode(successResult)
        let decodedSuccess = try decoder.decode(InvocationResult.self, from: successData)
        #expect(decodedSuccess == successResult)

        // Void case
        let voidResult = InvocationResult.void
        let voidData = try encoder.encode(voidResult)
        let decodedVoid = try decoder.decode(InvocationResult.self, from: voidData)
        #expect(decodedVoid == voidResult)

        // Failure case
        let failureResult = InvocationResult.failure(.timeout(10.0))
        let failureData = try encoder.encode(failureResult)
        let decodedFailure = try decoder.decode(InvocationResult.self, from: failureData)
        #expect(decodedFailure == failureResult)
    }

    @Test("Envelope hashable")
    func testEnvelopeHashable() throws {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let metadata = InvocationEnvelope.Metadata(timestamp: timestamp, version: "1.0", headers: [:])

        let envelope1 = InvocationEnvelope(
            callID: "123",
            recipientID: "sensor-1",
            target: "read",
            arguments: Data(),
            metadata: metadata
        )

        let envelope2 = InvocationEnvelope(
            callID: "123",
            recipientID: "sensor-1",
            target: "read",
            arguments: Data(),
            metadata: metadata
        )

        let envelope3 = InvocationEnvelope(
            callID: "456",
            recipientID: "sensor-2",
            target: "write",
            arguments: Data([1]),
            metadata: metadata
        )

        #expect(envelope1 == envelope2)
        #expect(envelope1 != envelope3)

        // Can be used in Set
        let envelopeSet: Set<InvocationEnvelope> = [envelope1, envelope2, envelope3]
        #expect(envelopeSet.count == 2)
    }

    @Test("ResponseEnvelope withExecutionTime helper")
    func testResponseEnvelopeWithExecutionTime() throws {
        let original = ResponseEnvelope(
            callID: "test-call",
            result: .success(Data([1, 2, 3])),
            metadata: .init(
                timestamp: Date(timeIntervalSince1970: 1000),
                headers: ["key": "value"]
            )
        )

        let enriched = original.withExecutionTime(0.5)

        #expect(enriched.callID == original.callID)
        #expect(enriched.result == original.result)
        #expect(enriched.metadata.executionTime == 0.5)
        #expect(enriched.metadata.timestamp == original.metadata.timestamp)
        #expect(enriched.metadata.headers == original.metadata.headers)
    }

    @Test("ResponseEnvelope withHeaders helper")
    func testResponseEnvelopeWithHeaders() throws {
        let original = ResponseEnvelope(
            callID: "test-call",
            result: .void,
            metadata: .init(headers: ["existing": "value"])
        )

        let enriched = original.withHeaders([
            "trace-id": "abc123",
            "span-id": "def456"
        ])

        #expect(enriched.callID == original.callID)
        #expect(enriched.result == original.result)
        #expect(enriched.metadata.headers.count == 3)
        #expect(enriched.metadata.headers["existing"] == "value")
        #expect(enriched.metadata.headers["trace-id"] == "abc123")
        #expect(enriched.metadata.headers["span-id"] == "def456")
    }

    @Test("ResponseEnvelope withHeaders merges and overwrites")
    func testResponseEnvelopeWithHeadersMerge() throws {
        let original = ResponseEnvelope(
            callID: "test-call",
            result: .void,
            metadata: .init(headers: ["key1": "old", "key2": "value2"])
        )

        let enriched = original.withHeaders(["key1": "new", "key3": "value3"])

        #expect(enriched.metadata.headers.count == 3)
        #expect(enriched.metadata.headers["key1"] == "new") // Overwritten
        #expect(enriched.metadata.headers["key2"] == "value2") // Preserved
        #expect(enriched.metadata.headers["key3"] == "value3") // Added
    }

    @Test("ResponseEnvelope withHeader helper")
    func testResponseEnvelopeWithHeader() throws {
        let original = ResponseEnvelope(
            callID: "test-call",
            result: .void,
            metadata: .init(headers: ["existing": "value"])
        )

        let enriched = original.withHeader("method", value: "readTemperature")

        #expect(enriched.metadata.headers.count == 2)
        #expect(enriched.metadata.headers["existing"] == "value")
        #expect(enriched.metadata.headers["method"] == "readTemperature")
    }

    @Test("ResponseEnvelope chaining helpers")
    func testResponseEnvelopeChainingHelpers() throws {
        let original = ResponseEnvelope(
            callID: "test-call",
            result: .success(Data([42]))
        )

        let enriched = original
            .withExecutionTime(0.5)
            .withHeader("trace-id", value: "abc123")
            .withHeaders(["span-id": "def456", "user-id": "user1"])

        #expect(enriched.callID == original.callID)
        #expect(enriched.result == original.result)
        #expect(enriched.metadata.executionTime == 0.5)
        #expect(enriched.metadata.headers["trace-id"] == "abc123")
        #expect(enriched.metadata.headers["span-id"] == "def456")
        #expect(enriched.metadata.headers["user-id"] == "user1")
    }
}
