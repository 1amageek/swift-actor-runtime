import Distributed
import Foundation

/// A Codable-based implementation of `InvocationDecoder`.
///
/// This decoder extracts distributed method arguments from an `InvocationEnvelope`,
/// decoding each argument sequentially.
///
/// ## Usage
///
/// ```swift
/// // Receive envelope from transport
/// let envelope: InvocationEnvelope = ...
///
/// // Create decoder
/// var decoder = try CodableInvocationDecoder(envelope: envelope)
///
/// // Use with executeDistributedTarget
/// try await executeDistributedTarget(
///     on: actor,
///     target: target,
///     invocationDecoder: &decoder,
///     handler: resultHandler
/// )
/// ```
public struct CodableInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable

    private var arguments: [Data]
    private var currentIndex: Int = 0

    /// Creates a decoder from an invocation envelope.
    ///
    /// - Parameter envelope: The envelope containing encoded arguments.
    /// - Throws: `RuntimeError.serializationFailed` if the envelope cannot be decoded.
    public init(envelope: InvocationEnvelope) throws {
        // Decode the array of Data blobs
        self.arguments = try JSONDecoder().decode([Data].self, from: envelope.arguments)
    }

    // MARK: - DistributedTargetInvocationDecoder

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        // Generic substitutions not currently stored in envelope
        // Return empty array (no generic parameters)
        return []
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard currentIndex < arguments.count else {
            throw RuntimeError.serializationFailed(
                "Attempted to decode argument at index \(currentIndex), but only \(arguments.count) arguments available"
            )
        }

        let data = arguments[currentIndex]
        currentIndex += 1

        do {
            return try JSONDecoder().decode(Argument.self, from: data)
        } catch {
            throw RuntimeError.serializationFailed(
                "Failed to decode argument at index \(currentIndex - 1): \(error)"
            )
        }
    }

    public mutating func decodeReturnType() throws -> Any.Type? {
        // Return type not stored in envelope
        // The caller already knows the expected return type
        return nil
    }

    public mutating func decodeErrorType() throws -> Any.Type? {
        // Error type not stored in envelope
        // Errors are wrapped in RuntimeError
        return nil
    }
}
