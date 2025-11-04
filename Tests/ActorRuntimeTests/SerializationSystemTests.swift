import Testing
import Foundation
@testable import ActorRuntime

@Suite("SerializationSystem Tests")
struct SerializationSystemTests {

    struct TestData: Codable, Equatable {
        let id: Int
        let name: String
        let values: [Double]
    }

    @Test("JSONSerializationSystem encode and decode")
    func testJSONSerializationEncodeDecode() throws {
        let serialization = JSONSerializationSystem()

        let original = TestData(
            id: 123,
            name: "test",
            values: [1.0, 2.5, 3.14]
        )

        // Encode
        let data = try serialization.encode(original)
        #expect(data.count > 0)

        // Decode
        let decoded = try serialization.decode(TestData.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSONSerializationSystem with custom encoder/decoder")
    func testJSONSerializationCustom() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let decoder = JSONDecoder()

        let serialization = JSONSerializationSystem(encoder: encoder, decoder: decoder)

        let original = TestData(id: 1, name: "test", values: [1.0])
        let data = try serialization.encode(original)

        // Pretty printed should have newlines
        let string = String(data: data, encoding: .utf8)
        #expect(string?.contains("\n") == true)

        let decoded = try serialization.decode(TestData.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSONSerializationSystem with primitive types")
    func testJSONSerializationPrimitives() throws {
        let serialization = JSONSerializationSystem()

        // Int
        let intData = try serialization.encode(42)
        let decodedInt = try serialization.decode(Int.self, from: intData)
        #expect(decodedInt == 42)

        // String
        let stringData = try serialization.encode("hello")
        let decodedString = try serialization.decode(String.self, from: stringData)
        #expect(decodedString == "hello")

        // Double
        let doubleData = try serialization.encode(3.14)
        let decodedDouble = try serialization.decode(Double.self, from: doubleData)
        #expect(decodedDouble == 3.14)

        // Bool
        let boolData = try serialization.encode(true)
        let decodedBool = try serialization.decode(Bool.self, from: boolData)
        #expect(decodedBool == true)
    }

    @Test("JSONSerializationSystem with arrays")
    func testJSONSerializationArrays() throws {
        let serialization = JSONSerializationSystem()

        let original = [1, 2, 3, 4, 5]
        let data = try serialization.encode(original)
        let decoded = try serialization.decode([Int].self, from: data)

        #expect(decoded == original)
    }

    @Test("JSONSerializationSystem with dictionaries")
    func testJSONSerializationDictionaries() throws {
        let serialization = JSONSerializationSystem()

        let original = ["key1": "value1", "key2": "value2"]
        let data = try serialization.encode(original)
        let decoded = try serialization.decode([String: String].self, from: data)

        #expect(decoded == original)
    }

    @Test("JSONSerializationSystem with optional values")
    func testJSONSerializationOptionals() throws {
        struct OptionalData: Codable, Equatable {
            let required: String
            let optional: Int?
        }

        let serialization = JSONSerializationSystem()

        // With value
        let withValue = OptionalData(required: "test", optional: 42)
        let withValueData = try serialization.encode(withValue)
        let decodedWithValue = try serialization.decode(OptionalData.self, from: withValueData)
        #expect(decodedWithValue == withValue)

        // Without value
        let withoutValue = OptionalData(required: "test", optional: nil)
        let withoutValueData = try serialization.encode(withoutValue)
        let decodedWithoutValue = try serialization.decode(OptionalData.self, from: withoutValueData)
        #expect(decodedWithoutValue == withoutValue)
    }

    @Test("JSONSerializationSystem with nested structures")
    func testJSONSerializationNested() throws {
        struct Inner: Codable, Equatable {
            let value: Int
        }

        struct Outer: Codable, Equatable {
            let name: String
            let inner: Inner
            let items: [Inner]
        }

        let serialization = JSONSerializationSystem()

        let original = Outer(
            name: "test",
            inner: Inner(value: 1),
            items: [Inner(value: 2), Inner(value: 3)]
        )

        let data = try serialization.encode(original)
        let decoded = try serialization.decode(Outer.self, from: data)

        #expect(decoded == original)
    }

    @Test("JSONSerializationSystem protocol conformance")
    func testJSONSerializationProtocolConformance() {
        let serialization = JSONSerializationSystem()

        // Verify it conforms to SerializationSystem protocol
        let _: any SerializationSystem = serialization
        #expect(true) // Test passes if compilation succeeds
    }

    @Test("JSONSerializationSystem decode error")
    func testJSONSerializationDecodeError() {
        let serialization = JSONSerializationSystem()

        // Invalid JSON data
        let invalidData = Data([0xFF, 0xFE])

        #expect(throws: Error.self) {
            try serialization.decode(TestData.self, from: invalidData)
        }
    }

    @Test("JSONSerializationSystem empty data")
    func testJSONSerializationEmptyData() throws {
        let serialization = JSONSerializationSystem()

        // Empty array
        let emptyArray: [Int] = []
        let data = try serialization.encode(emptyArray)
        let decoded = try serialization.decode([Int].self, from: data)
        #expect(decoded.isEmpty)

        // Empty dictionary
        let emptyDict: [String: String] = [:]
        let dictData = try serialization.encode(emptyDict)
        let decodedDict = try serialization.decode([String: String].self, from: dictData)
        #expect(decodedDict.isEmpty)

        // Empty string
        let emptyString = ""
        let stringData = try serialization.encode(emptyString)
        let decodedString = try serialization.decode(String.self, from: stringData)
        #expect(decodedString.isEmpty)
    }

    @Test("JSONSerializationSystem with dates")
    func testJSONSerializationDates() throws {
        struct DateData: Codable, Equatable {
            let timestamp: Date
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let serialization = JSONSerializationSystem(encoder: encoder, decoder: decoder)

        let original = DateData(timestamp: Date(timeIntervalSince1970: 1000))
        let data = try serialization.encode(original)
        let decoded = try serialization.decode(DateData.self, from: data)

        #expect(abs(decoded.timestamp.timeIntervalSince1970 - original.timestamp.timeIntervalSince1970) < 1.0)
    }

    @Test("JSONSerializationSystem large data")
    func testJSONSerializationLargeData() throws {
        let serialization = JSONSerializationSystem()

        // Large array
        let largeArray = Array(0..<10000)
        let data = try serialization.encode(largeArray)
        let decoded = try serialization.decode([Int].self, from: data)

        #expect(decoded.count == 10000)
        #expect(decoded.first == 0)
        #expect(decoded.last == 9999)
    }
}
