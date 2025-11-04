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
    private var genericSubstitutions: [String]
    private var currentIndex: Int = 0
    private let target: String  // Store for better error messages

    /// Creates a decoder from an invocation envelope.
    ///
    /// - Parameter envelope: The envelope containing encoded arguments.
    /// - Throws: `RuntimeError.serializationFailed` if the envelope cannot be decoded.
    public init(envelope: InvocationEnvelope) throws {
        // Decode the array of Data blobs
        self.arguments = try JSONDecoder().decode([Data].self, from: envelope.arguments)
        self.genericSubstitutions = envelope.genericSubstitutions
        self.target = envelope.target
    }

    // MARK: - DistributedTargetInvocationDecoder

    public mutating func decodeGenericSubstitutions() throws -> [Any.Type] {
        // Convert mangled type names back to Type objects
        return try genericSubstitutions.compactMap { mangledName in
            // Use Swift's internal _typeByName function to resolve mangled names
            guard let type = _typeByName(mangledName) else {
                throw RuntimeError.serializationFailed(
                    "Failed to resolve generic type from mangled name: \(mangledName)"
                )
            }
            return type
        }
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard currentIndex < arguments.count else {
            throw RuntimeError.serializationFailed(
                "Attempted to decode argument at index \(currentIndex), but only \(arguments.count) arguments available for method '\(target)'"
            )
        }

        let data = arguments[currentIndex]
        currentIndex += 1

        do {
            return try JSONDecoder().decode(Argument.self, from: data)
        } catch {
            throw RuntimeError.serializationFailed(
                "Failed to decode argument at index \(currentIndex - 1) as \(Argument.self) for method '\(target)': \(error.localizedDescription)"
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
