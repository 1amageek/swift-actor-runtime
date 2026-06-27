#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Standard errors for distributed actor runtime
///
/// These errors are serializable across process boundaries and provide
/// consistent error handling across all transport implementations.
///
/// ## Usage
///
/// ```swift
/// // Throw on server side
/// throw RuntimeError.actorNotFound("sensor-1")
///
/// // Serialize and send
/// let errorData = try JSONEncoder().encode(error)
///
/// // Deserialize on client side
/// let error = try JSONDecoder().decode(RuntimeError.self, from: errorData)
/// throw error  // Propagates to caller
/// ```
///
public enum RuntimeError: Error, Codable, Sendable, Hashable, CustomStringConvertible {
    /// Target actor not found in registry
    case actorNotFound(String)

    /// Actor instance was deallocated
    case actorDeallocated(String)

    /// Method not registered in method registry
    case methodNotFound(String)

    /// Method execution threw an error
    case executionFailed(String, underlying: String)

    /// Failed to serialize/deserialize data
    case serializationFailed(String)

    /// Transport layer failure
    case transportFailed(String)

    /// Invocation timed out
    case timeout(TimeInterval)

    /// Invalid envelope format
    case invalidEnvelope(String)

    /// Protocol version mismatch
    case versionMismatch(expected: String, actual: String)

    public var description: String {
        switch self {
        case .actorNotFound(let id):
            return "Actor not found: \(id)"
        case .actorDeallocated(let id):
            return "Actor deallocated: \(id)"
        case .methodNotFound(let name):
            return "Method not found: \(name)"
        case .executionFailed(let name, let underlying):
            return "Method execution failed (\(name)): \(underlying)"
        case .serializationFailed(let message):
            return "Serialization failed: \(message)"
        case .transportFailed(let message):
            return "Transport failed: \(message)"
        case .timeout(let duration):
            return "Invocation timed out after \(duration)s"
        case .invalidEnvelope(let message):
            return "Invalid envelope: \(message)"
        case .versionMismatch(let expected, let actual):
            return "Version mismatch: expected \(expected), got \(actual)"
        }
    }

    // MARK: - Codable Conformance

    private enum CodingKeys: String, CodingKey {
        case type, id, name, underlying, message, duration, expected, actual
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .actorNotFound(let id):
            try container.encode("actorNotFound", forKey: .type)
            try container.encode(id, forKey: .id)
        case .actorDeallocated(let id):
            try container.encode("actorDeallocated", forKey: .type)
            try container.encode(id, forKey: .id)
        case .methodNotFound(let name):
            try container.encode("methodNotFound", forKey: .type)
            try container.encode(name, forKey: .name)
        case .executionFailed(let name, let underlying):
            try container.encode("executionFailed", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(underlying, forKey: .underlying)
        case .serializationFailed(let message):
            try container.encode("serializationFailed", forKey: .type)
            try container.encode(message, forKey: .message)
        case .transportFailed(let message):
            try container.encode("transportFailed", forKey: .type)
            try container.encode(message, forKey: .message)
        case .timeout(let duration):
            try container.encode("timeout", forKey: .type)
            try container.encode(duration, forKey: .duration)
        case .invalidEnvelope(let message):
            try container.encode("invalidEnvelope", forKey: .type)
            try container.encode(message, forKey: .message)
        case .versionMismatch(let expected, let actual):
            try container.encode("versionMismatch", forKey: .type)
            try container.encode(expected, forKey: .expected)
            try container.encode(actual, forKey: .actual)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "actorNotFound":
            self = .actorNotFound(try container.decode(String.self, forKey: .id))
        case "actorDeallocated":
            self = .actorDeallocated(try container.decode(String.self, forKey: .id))
        case "methodNotFound":
            self = .methodNotFound(try container.decode(String.self, forKey: .name))
        case "executionFailed":
            self = .executionFailed(
                try container.decode(String.self, forKey: .name),
                underlying: try container.decode(String.self, forKey: .underlying)
            )
        case "serializationFailed":
            self = .serializationFailed(try container.decode(String.self, forKey: .message))
        case "transportFailed":
            self = .transportFailed(try container.decode(String.self, forKey: .message))
        case "timeout":
            self = .timeout(try container.decode(TimeInterval.self, forKey: .duration))
        case "invalidEnvelope":
            self = .invalidEnvelope(try container.decode(String.self, forKey: .message))
        case "versionMismatch":
            self = .versionMismatch(
                expected: try container.decode(String.self, forKey: .expected),
                actual: try container.decode(String.self, forKey: .actual)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown error type: \(type)"
            )
        }
    }
}
