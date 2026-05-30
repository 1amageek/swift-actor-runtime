import Foundation

/// Unified message type for bidirectional communication
///
/// Wraps both invocation requests and responses into a single type,
/// enabling symmetric communication where either peer can send any message type.
///
/// ## Overview
///
/// The `Envelope` type simplifies transport implementations by providing
/// a single type to send and receive. Pattern match on the cases to handle
/// each message type appropriately.
///
/// ## Usage
///
/// ```swift
/// // Sending
/// try await transport.send(.invocation(envelope))
/// try await transport.send(.response(response))
///
/// // Receiving
/// for try await envelope in transport.messages {
///     switch envelope {
///     case .invocation(let inv):
///         // Handle incoming method call
///     case .response(let res):
///         // Handle response to a previous call
///     }
/// }
/// ```
///
public enum Envelope: Codable, Sendable, Hashable {
    /// A distributed method invocation request
    case invocation(InvocationEnvelope)
    /// A response to a previous invocation
    case response(ResponseEnvelope)
}

/// Universal invocation envelope for distributed method calls
///
/// Represents a remote procedure call in a transport-agnostic way.
/// Transports serialize this to their native format (JSON, Protobuf, etc.)
///
/// ## Usage
///
/// ```swift
/// let envelope = InvocationEnvelope(
///     recipientID: "sensor-1",
///     target: "readTemperature",
///     arguments: []
/// )
/// ```
///
public struct InvocationEnvelope: Codable, Sendable, Hashable {
    /// Unique identifier for this invocation (for matching responses)
    public let callID: String

    /// Target actor identifier (implementation-specific format)
    public let recipientID: String

    /// Optional sender actor identifier
    public let senderID: String?

    /// Method identifier (typically mangled Swift name)
    public let target: String

    /// Generic type substitutions (mangled type names)
    public let genericSubstitutions: [String]

    /// Serialized method arguments, one `Data` blob per parameter, in call order.
    ///
    /// Storing arguments as a list (rather than a single blob holding an encoded
    /// `[Data]`) avoids encoding the argument bytes twice — once per argument and
    /// again when the surrounding container is serialized — which would otherwise
    /// base64-expand every argument an extra time.
    public let arguments: [Data]

    /// Invocation metadata
    public let metadata: Metadata

    /// Metadata associated with an invocation request
    ///
    /// Contains contextual information about the invocation such as timing,
    /// protocol version, and custom headers for tracing or transport-specific needs.
    public struct Metadata: Codable, Sendable, Hashable {
        /// The timestamp when the invocation was created
        public let timestamp: Date

        /// Protocol version for compatibility checking
        public let version: String

        /// Custom headers for transport-specific needs (e.g., tracing, authentication)
        public let headers: [String: String]

        /// Creates new invocation metadata.
        ///
        /// - Parameters:
        ///   - timestamp: When the invocation was created. Defaults to now.
        ///   - version: Protocol version string. Defaults to `"1.0"`.
        ///   - headers: Custom key-value headers. Defaults to empty.
        public init(
            timestamp: Date = Date(),
            version: String = "1.0",
            headers: [String: String] = [:]
        ) {
            self.timestamp = timestamp
            self.version = version
            self.headers = headers
        }
    }

    /// Creates a new invocation envelope.
    ///
    /// - Parameters:
    ///   - callID: Unique identifier for this call. Defaults to a new UUID string.
    ///   - recipientID: The target actor's identifier.
    ///   - senderID: Optional identifier of the sending actor.
    ///   - target: The method identifier (typically a mangled Swift function name).
    ///   - genericSubstitutions: Mangled type names for generic type parameters.
    ///   - arguments: Serialized method arguments, one `Data` blob per parameter.
    ///   - metadata: Associated metadata. Defaults to new metadata with current timestamp.
    public init(
        callID: String = UUID().uuidString,
        recipientID: String,
        senderID: String? = nil,
        target: String,
        genericSubstitutions: [String] = [],
        arguments: [Data],
        metadata: Metadata = Metadata()
    ) {
        self.callID = callID
        self.recipientID = recipientID
        self.senderID = senderID
        self.target = target
        self.genericSubstitutions = genericSubstitutions
        self.arguments = arguments
        self.metadata = metadata
    }
}

/// Universal response envelope
///
/// Represents the result of a distributed method call.
/// Contains either successful result data or error information.
///
/// ## Usage
///
/// ```swift
/// // Success
/// let response = ResponseEnvelope(
///     callID: envelope.callID,
///     result: .success(resultData)
/// )
///
/// // Void return
/// let response = ResponseEnvelope(
///     callID: envelope.callID,
///     result: .void
/// )
///
/// // Error
/// let response = ResponseEnvelope(
///     callID: envelope.callID,
///     result: .failure(.actorNotFound("sensor-1"))
/// )
/// ```
///
public struct ResponseEnvelope: Codable, Sendable, Hashable {
    /// Matches the InvocationEnvelope.callID
    public let callID: String

    /// Result of the invocation (success or failure)
    public let result: InvocationResult

    /// Response metadata
    public let metadata: Metadata

    /// Metadata associated with a response
    ///
    /// Contains contextual information about the response including timing
    /// information and custom headers for tracing or debugging.
    public struct Metadata: Codable, Sendable, Hashable {
        /// The timestamp when the response was created
        public let timestamp: Date

        /// The method execution time in seconds, if measured
        public let executionTime: TimeInterval?

        /// Custom headers for transport-specific needs (e.g., tracing, debugging)
        public let headers: [String: String]

        /// Creates new response metadata.
        ///
        /// - Parameters:
        ///   - timestamp: When the response was created. Defaults to now.
        ///   - executionTime: How long the method took to execute, if measured.
        ///   - headers: Custom key-value headers. Defaults to empty.
        public init(
            timestamp: Date = Date(),
            executionTime: TimeInterval? = nil,
            headers: [String: String] = [:]
        ) {
            self.timestamp = timestamp
            self.executionTime = executionTime
            self.headers = headers
        }
    }

    /// Creates a new response envelope.
    ///
    /// - Parameters:
    ///   - callID: The call identifier matching the original invocation.
    ///   - result: The result of the invocation (success, void, or failure).
    ///   - metadata: Associated metadata. Defaults to new metadata with current timestamp.
    public init(
        callID: String,
        result: InvocationResult,
        metadata: Metadata = Metadata()
    ) {
        self.callID = callID
        self.result = result
        self.metadata = metadata
    }
}

// MARK: - ResponseEnvelope Convenience Methods

extension ResponseEnvelope {
    /// Returns a new ResponseEnvelope with the specified execution time.
    ///
    /// This is useful when you need to measure and record the execution time
    /// of a distributed method call after the initial envelope is created.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let startTime = Date()
    /// // ... execute distributed method ...
    /// let executionTime = Date().timeIntervalSince(startTime)
    /// let enrichedResponse = response.withExecutionTime(executionTime)
    /// ```
    ///
    /// - Parameter time: The execution time in seconds.
    /// - Returns: A new ResponseEnvelope with updated metadata.
    public func withExecutionTime(_ time: TimeInterval) -> ResponseEnvelope {
        return ResponseEnvelope(
            callID: callID,
            result: result,
            metadata: Metadata(
                timestamp: metadata.timestamp,
                executionTime: time,
                headers: metadata.headers
            )
        )
    }

    /// Returns a new ResponseEnvelope with additional headers merged.
    ///
    /// This is useful for adding distributed tracing information, request IDs,
    /// or other contextual metadata to the response.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let enrichedResponse = response.withHeaders([
    ///     "trace-id": "abc123",
    ///     "span-id": "def456"
    /// ])
    /// ```
    ///
    /// - Parameter additionalHeaders: Headers to add or update. If a header key
    ///   already exists, the new value will replace the old value.
    /// - Returns: A new ResponseEnvelope with merged headers.
    public func withHeaders(_ additionalHeaders: [String: String]) -> ResponseEnvelope {
        var headers = metadata.headers
        headers.merge(additionalHeaders) { _, new in new }

        return ResponseEnvelope(
            callID: callID,
            result: result,
            metadata: Metadata(
                timestamp: metadata.timestamp,
                executionTime: metadata.executionTime,
                headers: headers
            )
        )
    }

    /// Returns a new ResponseEnvelope with a single header added or updated.
    ///
    /// This is a convenience method for adding a single header without creating
    /// a dictionary.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let enrichedResponse = response.withHeader("method", value: "readTemperature")
    /// ```
    ///
    /// - Parameters:
    ///   - key: The header key.
    ///   - value: The header value.
    /// - Returns: A new ResponseEnvelope with the updated header.
    public func withHeader(_ key: String, value: String) -> ResponseEnvelope {
        return withHeaders([key: value])
    }
}

/// Result of a remote invocation
///
/// Represents the outcome of a distributed method call, distinguishing between
/// successful executions (with or without return value) and failures.
///
/// ## Overview
///
/// Use this enum to wrap the result of executing a distributed method.
/// The three cases cover all possible outcomes:
/// - `success`: Method returned a value (serialized as `Data`)
/// - `void`: Method completed successfully with no return value
/// - `failure`: Method threw an error
///
/// ## Usage
///
/// ```swift
/// // Creating results
/// let successResult = InvocationResult.success(encodedData)
/// let voidResult = InvocationResult.void
/// let errorResult = InvocationResult.failure(.actorNotFound("sensor-1"))
///
/// // Handling results
/// switch result {
/// case .success(let data):
///     let value = try decoder.decode(MyType.self, from: data)
/// case .void:
///     // No return value to process
/// case .failure(let error):
///     throw error
/// }
/// ```
///
public enum InvocationResult: Codable, Sendable, Hashable {
    /// Successful execution with a serialized return value
    case success(Data)

    /// Successful execution with no return value (void method)
    case void

    /// Execution failed with an error
    case failure(RuntimeError)

    // MARK: - Codable Conformance

    private enum CodingKeys: String, CodingKey {
        case type, data, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .success(let data):
            try container.encode("success", forKey: .type)
            try container.encode(data, forKey: .data)
        case .void:
            try container.encode("void", forKey: .type)
        case .failure(let error):
            try container.encode("failure", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "success":
            self = .success(try container.decode(Data.self, forKey: .data))
        case "void":
            self = .void
        case "failure":
            self = .failure(try container.decode(RuntimeError.self, forKey: .error))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown result type: \(type)"
            )
        }
    }
}
