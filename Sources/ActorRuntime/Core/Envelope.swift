import Foundation

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
///     arguments: Data()
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

    /// Serialized method arguments
    public let arguments: Data

    /// Invocation metadata
    public let metadata: Metadata

    public struct Metadata: Codable, Sendable, Hashable {
        /// When the invocation was created
        public let timestamp: Date

        /// Protocol version for compatibility
        public let version: String

        /// Custom headers for transport-specific needs
        public let headers: [String: String]

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

    public init(
        callID: String = UUID().uuidString,
        recipientID: String,
        senderID: String? = nil,
        target: String,
        arguments: Data,
        metadata: Metadata = Metadata()
    ) {
        self.callID = callID
        self.recipientID = recipientID
        self.senderID = senderID
        self.target = target
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

    public struct Metadata: Codable, Sendable, Hashable {
        /// When the response was created
        public let timestamp: Date

        /// How long the method took to execute (optional)
        public let executionTime: TimeInterval?

        /// Custom headers
        public let headers: [String: String]

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

/// Result of a remote invocation
///
/// Distinguishes between successful executions (with or without return value)
/// and failures.
///
public enum InvocationResult: Codable, Sendable, Hashable {
    /// Successful execution with return value
    case success(Data)

    /// Void return (method completed successfully with no value)
    case void

    /// Method threw an error
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
