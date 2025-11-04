import Foundation

/// Pluggable serialization system for method arguments and results
///
/// Allows transports to choose their preferred serialization format:
/// - JSON (default, human-readable, debugging-friendly)
/// - Protocol Buffers (efficient, schema-based)
/// - MessagePack (compact binary)
/// - Custom formats
///
/// ## Usage
///
/// ```swift
/// // Use JSON serialization (default)
/// let serialization = JSONSerializationSystem()
/// let data = try serialization.encode(myValue)
/// let decoded = try serialization.decode(MyType.self, from: data)
/// ```
///
public protocol SerializationSystem: Sendable {
    /// Encode a value to Data
    ///
    /// - Parameter value: The value to encode
    /// - Returns: Encoded data
    /// - Throws: Encoding errors
    ///
    func encode<T: Encodable>(_ value: T) throws -> Data

    /// Decode Data to a value
    ///
    /// - Parameters:
    ///   - type: The type to decode
    ///   - data: The data to decode from
    /// - Returns: Decoded value
    /// - Throws: Decoding errors
    ///
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

/// JSON-based serialization (default)
///
/// Human-readable format, good for debugging and universal compatibility.
///
/// ## Thread Safety
///
/// `JSONSerializationSystem` is thread-safe when used with immutable encoder/decoder configurations.
/// The default `JSONEncoder` and `JSONDecoder` are safe for concurrent use as long as their
/// properties are not modified after initialization.
///
/// **Safe usage** (recommended):
/// ```swift
/// // Configure once, then use concurrently
/// let encoder = JSONEncoder()
/// encoder.dateEncodingStrategy = .iso8601
/// let serialization = JSONSerializationSystem(encoder: encoder)
/// // Can now be safely used from multiple tasks
/// ```
///
/// **Unsafe usage** (avoid):
/// ```swift
/// let encoder = JSONEncoder()
/// let serialization = JSONSerializationSystem(encoder: encoder)
/// Task {
///     encoder.dateEncodingStrategy = .iso8601  // ❌ Race condition!
///     try serialization.encode(data)
/// }
/// ```
///
/// If you need to modify encoder/decoder properties at runtime, create separate instances
/// per configuration instead of mutating shared instances.
///
/// ## Configuration
///
/// ```swift
/// let encoder = JSONEncoder()
/// encoder.dateEncodingStrategy = .iso8601
/// encoder.outputFormatting = .prettyPrinted
///
/// let decoder = JSONDecoder()
/// decoder.dateDecodingStrategy = .iso8601
///
/// let serialization = JSONSerializationSystem(encoder: encoder, decoder: decoder)
/// ```
///
public struct JSONSerializationSystem: SerializationSystem {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Initialize with default encoder/decoder
    public init() {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Initialize with custom encoder/decoder
    ///
    /// - Parameters:
    ///   - encoder: Custom JSON encoder
    ///   - decoder: Custom JSON decoder
    ///
    public init(encoder: JSONEncoder, decoder: JSONDecoder) {
        self.encoder = encoder
        self.decoder = decoder
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
