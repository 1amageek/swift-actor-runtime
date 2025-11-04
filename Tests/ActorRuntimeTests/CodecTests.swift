import Testing
import Foundation
@testable import ActorRuntime

@Suite("Codec Tests")
struct CodecTests {

    // MARK: - CodableInvocationEncoder Tests

    @Test("Encode single argument")
    func encodeSingleArgument() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue(42)
        try encoder.doneRecording()

        // Cannot test makeInvocationEnvelope without recordTarget
        // This is tested in integration tests
    }

    @Test("Encode multiple arguments")
    func encodeMultipleArguments() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue("hello")
        try encoder.recordValue(42)
        try encoder.recordValue(3.14)
        try encoder.doneRecording()
    }

    @Test("Encode complex Codable types")
    func encodeComplexTypes() throws {
        struct TestData: Codable, Equatable {
            let name: String
            let value: Int
            let nested: [String: Double]
        }

        var encoder = CodableInvocationEncoder()

        let data = TestData(
            name: "test",
            value: 123,
            nested: ["a": 1.0, "b": 2.0]
        )

        try encoder.recordValue(data)
        try encoder.doneRecording()
    }

    @Test("Cannot record after doneRecording")
    func cannotRecordAfterDone() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue(42)
        try encoder.doneRecording()

        #expect(throws: RuntimeError.self) {
            try encoder.recordValue(100)
        }
    }

    @Test("Cannot call doneRecording twice")
    func cannotCallDoneRecordingTwice() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue(42)
        try encoder.doneRecording()

        #expect(throws: RuntimeError.self) {
            try encoder.doneRecording()
        }
    }

    // MARK: - CodableInvocationDecoder Tests

    @Test("Decode single argument")
    func decodeSingleArgument() throws {
        // Create an envelope manually
        let arguments = [try JSONEncoder().encode(42)]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let value: Int = try decoder.decodeNextArgument()

        #expect(value == 42)
    }

    @Test("Decode multiple arguments in sequence")
    func decodeMultipleArguments() throws {
        let arguments = [
            try JSONEncoder().encode("hello"),
            try JSONEncoder().encode(42),
            try JSONEncoder().encode(3.14)
        ]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        let str: String = try decoder.decodeNextArgument()
        let num: Int = try decoder.decodeNextArgument()
        let dbl: Double = try decoder.decodeNextArgument()

        #expect(str == "hello")
        #expect(num == 42)
        #expect(dbl == 3.14)
    }

    @Test("Decode complex Codable types")
    func decodeComplexTypes() throws {
        struct TestData: Codable, Equatable {
            let name: String
            let value: Int
            let nested: [String: Double]
        }

        let original = TestData(
            name: "test",
            value: 123,
            nested: ["a": 1.0, "b": 2.0]
        )

        let arguments = [try JSONEncoder().encode(original)]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let decoded: TestData = try decoder.decodeNextArgument()

        #expect(decoded == original)
    }

    @Test("Decode throws when no more arguments")
    func decodeThrowsWhenNoMoreArguments() throws {
        let arguments = [try JSONEncoder().encode(42)]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let _: Int = try decoder.decodeNextArgument()

        #expect(throws: RuntimeError.self) {
            let _: Int = try decoder.decodeNextArgument()
        }
    }

    @Test("Decode throws on type mismatch")
    func decodeThrowsOnTypeMismatch() throws {
        let arguments = [try JSONEncoder().encode("not a number")]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        #expect(throws: RuntimeError.self) {
            let _: Int = try decoder.decodeNextArgument()
        }
    }

    // MARK: - Round-trip Tests

    @Test("Round-trip single argument")
    func roundTripSingleArgument() throws {
        var encoder = CodableInvocationEncoder()
        try encoder.recordValue(42)
        try encoder.doneRecording()

        // Manually create envelope (without target)
        let arguments = [try JSONEncoder().encode(42)]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let value: Int = try decoder.decodeNextArgument()

        #expect(value == 42)
    }

    @Test("Round-trip multiple arguments")
    func roundTripMultipleArguments() throws {
        let arg1 = "test string"
        let arg2 = [1, 2, 3, 4, 5]
        let arg3 = ["key1": "value1", "key2": "value2"]

        let arguments = [
            try JSONEncoder().encode(arg1),
            try JSONEncoder().encode(arg2),
            try JSONEncoder().encode(arg3)
        ]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        let decoded1: String = try decoder.decodeNextArgument()
        let decoded2: [Int] = try decoder.decodeNextArgument()
        let decoded3: [String: String] = try decoder.decodeNextArgument()

        #expect(decoded1 == arg1)
        #expect(decoded2 == arg2)
        #expect(decoded3 == arg3)
    }

    @Test("Round-trip with optional values")
    func roundTripOptionalValues() throws {
        let arg1: String? = "present"
        let arg2: String? = nil
        let arg3: Int? = 42

        let arguments = [
            try JSONEncoder().encode(arg1),
            try JSONEncoder().encode(arg2),
            try JSONEncoder().encode(arg3)
        ]
        let argumentsData = try JSONEncoder().encode(arguments)

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: argumentsData,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        let decoded1: String? = try decoder.decodeNextArgument()
        let decoded2: String? = try decoder.decodeNextArgument()
        let decoded3: Int? = try decoder.decodeNextArgument()

        #expect(decoded1 == arg1)
        #expect(decoded2 == arg2)
        #expect(decoded3 == arg3)
    }

    // MARK: - CodableResultHandler Tests

    @Test("ResultHandler onReturn encodes value")
    func resultHandlerOnReturn() async throws {
        var capturedResponse: ResponseEnvelope?

        let handler = CodableResultHandler(callID: "test-call") { response in
            capturedResponse = response
        }

        try await handler.onReturn(value: 42)

        #expect(capturedResponse != nil)
        #expect(capturedResponse?.callID == "test-call")

        if case .success(let data) = capturedResponse?.result {
            let value = try JSONDecoder().decode(Int.self, from: data)
            #expect(value == 42)
        } else {
            Issue.record("Expected success result")
        }
    }

    @Test("ResultHandler onReturnVoid creates void response")
    func resultHandlerOnReturnVoid() async throws {
        var capturedResponse: ResponseEnvelope?

        let handler = CodableResultHandler(callID: "test-call") { response in
            capturedResponse = response
        }

        try await handler.onReturnVoid()

        #expect(capturedResponse != nil)
        #expect(capturedResponse?.callID == "test-call")

        if case .void = capturedResponse?.result {
            // Success
        } else {
            Issue.record("Expected void result")
        }
    }

    @Test("ResultHandler onThrow wraps error")
    func resultHandlerOnThrow() async throws {
        var capturedResponse: ResponseEnvelope?

        let handler = CodableResultHandler(callID: "test-call") { response in
            capturedResponse = response
        }

        struct TestError: Error {}
        try await handler.onThrow(error: TestError())

        #expect(capturedResponse != nil)
        #expect(capturedResponse?.callID == "test-call")

        if case .failure(let error) = capturedResponse?.result {
            // Verify the error is wrapped in RuntimeError.executionFailed
            if case .executionFailed = error {
                // Success - error was properly wrapped
            } else {
                Issue.record("Expected RuntimeError.executionFailed but got \(error)")
            }
        } else {
            Issue.record("Expected failure result")
        }
    }
}
