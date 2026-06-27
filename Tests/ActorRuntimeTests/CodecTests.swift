import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Distributed
@testable import ActorRuntime

/// File-scope fixture used to verify that user-defined types survive
/// generic-substitution round-tripping.
///
/// Declared `internal` (not `private`): private/local types carry a file
/// discriminator in their mangled name that `_typeByName` cannot resolve at
/// runtime, which is a genuine limitation of the Swift runtime shared with
/// swift-distributed-actors, not of this encoder.
struct SubstitutionFixture: Codable, Sendable {
    let value: Int
}

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

    @Test("Access encoded arguments after doneRecording")
    func accessEncodedArguments() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue("hello")
        try encoder.recordValue(42)
        try encoder.recordValue(3.14)
        try encoder.doneRecording()

        let arguments = try encoder.encodedArguments()

        #expect(arguments.count == 3)

        // Verify each argument can be decoded
        let arg1 = try JSONDecoder().decode(String.self, from: arguments[0])
        let arg2 = try JSONDecoder().decode(Int.self, from: arguments[1])
        let arg3 = try JSONDecoder().decode(Double.self, from: arguments[2])

        #expect(arg1 == "hello")
        #expect(arg2 == 42)
        #expect(arg3 == 3.14)
    }

    @Test("Cannot access arguments before doneRecording")
    func cannotAccessArgumentsBeforeDone() throws {
        var encoder = CodableInvocationEncoder()

        try encoder.recordValue(42)

        #expect(throws: RuntimeError.self) {
            _ = try encoder.encodedArguments()
        }
    }

    // MARK: - CodableInvocationDecoder Tests

    @Test("Decode single argument")
    func decodeSingleArgument() throws {
        // Create an envelope manually
        let arguments = [try JSONEncoder().encode(42)]

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let decoded: TestData = try decoder.decodeNextArgument()

        #expect(decoded == original)
    }

    @Test("Decode throws when no more arguments")
    func decodeThrowsWhenNoMoreArguments() throws {
        let arguments = [try JSONEncoder().encode(42)]

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
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

    // MARK: - Improved Error Message Tests

    @Test("Decoder error includes method name when no arguments available")
    func decoderErrorIncludesMethodNameForNoArguments() throws {
        let arguments: [Data] = []

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "testMethod",
            arguments: arguments,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        do {
            let _: Int = try decoder.decodeNextArgument()
            Issue.record("Expected error to be thrown")
        } catch let error as RuntimeError {
            if case .serializationFailed(let message) = error {
                #expect(message.contains("testMethod"))
                #expect(message.contains("index 0"))
                #expect(message.contains("0 arguments available"))
            } else {
                Issue.record("Expected serializationFailed error but got \(error)")
            }
        }
    }

    @Test("Decoder error includes method name and type on type mismatch")
    func decoderErrorIncludesMethodNameAndTypeOnMismatch() throws {
        let arguments = [try JSONEncoder().encode("not a number")]

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "readTemperature",
            arguments: arguments,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        do {
            let _: Int = try decoder.decodeNextArgument()
            Issue.record("Expected error to be thrown")
        } catch let error as RuntimeError {
            if case .serializationFailed(let message) = error {
                #expect(message.contains("readTemperature"))
                #expect(message.contains("Int"))
                #expect(message.contains("index 0"))
            } else {
                Issue.record("Expected serializationFailed error but got \(error)")
            }
        }
    }

    @Test("Decoder error message shows correct index for multiple arguments")
    func decoderErrorShowsCorrectIndexForMultipleArguments() throws {
        let arguments = [
            try JSONEncoder().encode("first"),
            try JSONEncoder().encode("second"),
            try JSONEncoder().encode("third")
        ]

        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            senderID: nil,
            target: "multiArgMethod",
            arguments: arguments,
            metadata: .init()
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)

        // Decode first two successfully
        let _: String = try decoder.decodeNextArgument()
        let _: String = try decoder.decodeNextArgument()

        // Try to decode third with wrong type
        do {
            let _: Int = try decoder.decodeNextArgument()
            Issue.record("Expected error to be thrown")
        } catch let error as RuntimeError {
            if case .serializationFailed(let message) = error {
                #expect(message.contains("multiArgMethod"))
                #expect(message.contains("index 2"))
                #expect(message.contains("Int"))
            } else {
                Issue.record("Expected serializationFailed error but got \(error)")
            }
        }
    }

    // MARK: - Generic Substitution Round-trip Tests

    /// Records a single generic substitution through the encoder, rebuilds an
    /// envelope, and asserts the decoder resolves it back to the exact same type.
    ///
    /// This exercises the full encoder -> envelope -> decoder contract that the
    /// Swift runtime relies on for generic distributed methods and actors.
    private func assertGenericSubstitutionRoundTrips<T>(_ type: T.Type) throws {
        var encoder = CodableInvocationEncoder()
        try encoder.recordGenericSubstitution(type)
        try encoder.doneRecording()
        encoder.recordTarget(RemoteCallTarget("testTarget"))

        let envelope = try encoder.makeInvocationEnvelope(recipientID: "test-actor")

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let resolved = try decoder.decodeGenericSubstitutions()

        #expect(resolved.count == 1)
        let resolvedType = try #require(resolved.first)
        #expect(
            ObjectIdentifier(resolvedType) == ObjectIdentifier(type),
            "Expected \(type) but resolved \(resolvedType)"
        )
    }

    @Test("Generic substitution round-trips for primitive types")
    func genericSubstitutionPrimitives() throws {
        try assertGenericSubstitutionRoundTrips(Int.self)
        try assertGenericSubstitutionRoundTrips(String.self)
        try assertGenericSubstitutionRoundTrips(Double.self)
        try assertGenericSubstitutionRoundTrips(Bool.self)
    }

    @Test("Generic substitution round-trips for composite types")
    func genericSubstitutionComposites() throws {
        // These all fail with String(reflecting:)/_typeByName and only resolve
        // correctly once mangled names are recorded.
        try assertGenericSubstitutionRoundTrips([Int].self)
        try assertGenericSubstitutionRoundTrips([String: Int].self)
        try assertGenericSubstitutionRoundTrips(Optional<Int>.self)
        try assertGenericSubstitutionRoundTrips([[String]].self)
    }

    @Test("Generic substitution round-trips for user-defined types")
    func genericSubstitutionUserTypes() throws {
        try assertGenericSubstitutionRoundTrips(SubstitutionFixture.self)
        try assertGenericSubstitutionRoundTrips([SubstitutionFixture].self)
        try assertGenericSubstitutionRoundTrips(Optional<SubstitutionFixture>.self)
    }

    @Test("Multiple generic substitutions preserve type and order")
    func multipleGenericSubstitutions() throws {
        var encoder = CodableInvocationEncoder()
        try encoder.recordGenericSubstitution(Int.self)
        try encoder.recordGenericSubstitution([String].self)
        try encoder.recordGenericSubstitution(SubstitutionFixture.self)
        try encoder.doneRecording()
        encoder.recordTarget(RemoteCallTarget("testTarget"))

        let envelope = try encoder.makeInvocationEnvelope(recipientID: "test-actor")

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        let resolved = try decoder.decodeGenericSubstitutions()

        #expect(resolved.count == 3)
        #expect(ObjectIdentifier(resolved[0]) == ObjectIdentifier(Int.self))
        #expect(ObjectIdentifier(resolved[1]) == ObjectIdentifier([String].self))
        #expect(ObjectIdentifier(resolved[2]) == ObjectIdentifier(SubstitutionFixture.self))
    }

    @Test("Unresolvable mangled name surfaces a serialization error")
    func unresolvableGenericSubstitutionThrows() throws {
        // A bogus name must not silently resolve or be dropped.
        let envelope = InvocationEnvelope(
            recipientID: "test-actor",
            target: "testTarget",
            genericSubstitutions: ["this-is-not-a-valid-mangled-name"],
            arguments: []
        )

        var decoder = try CodableInvocationDecoder(envelope: envelope)
        #expect(throws: RuntimeError.self) {
            _ = try decoder.decodeGenericSubstitutions()
        }
    }
}
