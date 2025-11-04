import Testing
import Foundation
@testable import ActorRuntime

@Suite("RuntimeError Tests")
struct RuntimeErrorTests {

    @Test("RuntimeError encoding and decoding")
    func testErrorEncodingDecoding() throws {
        let errors: [RuntimeError] = [
            .actorNotFound("sensor-1"),
            .actorDeallocated("sensor-2"),
            .methodNotFound("readTemperature"),
            .executionFailed("getValue", underlying: "Division by zero"),
            .serializationFailed("Invalid JSON"),
            .transportFailed("Connection lost"),
            .timeout(10.0),
            .invalidEnvelope("Missing callID"),
            .versionMismatch(expected: "1.0", actual: "2.0")
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for error in errors {
            // Encode
            let data = try encoder.encode(error)
            #expect(data.count > 0)

            // Decode
            let decoded = try decoder.decode(RuntimeError.self, from: data)

            // Verify equality
            #expect(decoded == error)
        }
    }

    @Test("RuntimeError descriptions")
    func testErrorDescriptions() {
        #expect(RuntimeError.actorNotFound("sensor-1").description.contains("Actor not found"))
        #expect(RuntimeError.actorDeallocated("sensor-1").description.contains("Actor deallocated"))
        #expect(RuntimeError.methodNotFound("read").description.contains("Method not found"))
        #expect(RuntimeError.executionFailed("read", underlying: "error").description.contains("Method execution failed"))
        #expect(RuntimeError.serializationFailed("msg").description.contains("Serialization failed"))
        #expect(RuntimeError.transportFailed("msg").description.contains("Transport failed"))
        #expect(RuntimeError.timeout(5.0).description.contains("timed out"))
        #expect(RuntimeError.invalidEnvelope("msg").description.contains("Invalid envelope"))
        #expect(RuntimeError.versionMismatch(expected: "1.0", actual: "2.0").description.contains("Version mismatch"))
    }

    @Test("RuntimeError hashable")
    func testErrorHashable() {
        let error1 = RuntimeError.actorNotFound("sensor-1")
        let error2 = RuntimeError.actorNotFound("sensor-1")
        let error3 = RuntimeError.actorNotFound("sensor-2")

        #expect(error1 == error2)
        #expect(error1 != error3)

        // Can be used in Set
        let errorSet: Set<RuntimeError> = [error1, error2, error3]
        #expect(errorSet.count == 2)
    }
}
