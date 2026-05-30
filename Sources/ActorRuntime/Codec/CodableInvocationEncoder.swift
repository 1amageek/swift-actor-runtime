import Distributed
import Foundation

/// A Codable-based implementation of `InvocationEncoder`.
///
/// This encoder records distributed method arguments as individually encoded `Data` blobs,
/// allowing transport-agnostic serialization of method calls.
///
/// ## Usage
///
/// ```swift
/// func remoteCall<Act, Err, Res>(
///     on actor: Act,
///     target: RemoteCallTarget,
///     invocation: inout InvocationEncoder,
///     throwing: Err.Type,
///     returning: Res.Type
/// ) async throws -> Res {
///     var encoder = invocation as! CodableInvocationEncoder
///     encoder.recordTarget(target)
///
///     let envelope = try encoder.makeInvocationEnvelope(
///         recipientID: actor.id.description
///     )
///
///     // Send envelope over transport...
/// }
/// ```
public struct CodableInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable

    /// Internal state of the encoder.
    private enum State {
        case recording
        case finished
        case consumed
    }

    private var state: State = .recording
    private var arguments: [Data] = []
    private var target: String?
    private var genericSubstitutions: [String] = []

    /// Reused across all arguments of a single invocation to avoid allocating a
    /// fresh encoder per `recordArgument` call.
    private let jsonEncoder = JSONEncoder()

    public init() {}

    // MARK: - DistributedTargetInvocationEncoder

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        guard state == .recording else {
            throw RuntimeError.invalidState("Cannot record generic substitution after encoding")
        }
        // Record the runtime-mangled type name so it can be resolved back to a
        // concrete type via `_typeByName` on the receiving side.
        //
        // `_mangledTypeName` produces a stable, machine-resolvable representation
        // (e.g. "SaySiG" for [Int]). `String(reflecting:)` produces a
        // human-readable name (e.g. "Swift.Array<Swift.Int>") that `_typeByName`
        // cannot resolve for generic, optional, collection, or user-defined types.
        // Fall back to `_typeName` only when mangling is unavailable, matching
        // swift-distributed-actors' ClusterInvocationEncoder.
        genericSubstitutions.append(_mangledTypeName(type) ?? _typeName(type))
    }

    public mutating func recordArgument<Value>(_ argument: RemoteCallArgument<Value>) throws where Value: Codable {
        guard state == .recording else {
            throw RuntimeError.invalidState("Cannot record argument after encoding")
        }

        let data = try jsonEncoder.encode(argument.value)
        arguments.append(data)
    }

    /// Helper method for testing: record a raw value without wrapping in RemoteCallArgument.
    ///
    /// - Note: This is primarily for testing. Production code should use the standard `recordArgument` method.
    internal mutating func recordValue<Value: Codable>(_ value: Value) throws {
        guard state == .recording else {
            throw RuntimeError.invalidState("Cannot record argument after encoding")
        }

        let data = try jsonEncoder.encode(value)
        arguments.append(data)
    }

    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {
        // Return type information not stored in envelope
        // (it's known at call site)
    }

    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
        // Error type information not stored in envelope
        // (handled via RuntimeError wrapper)
    }

    public mutating func doneRecording() throws {
        guard state == .recording else {
            throw RuntimeError.invalidState("Already finished recording")
        }
        state = .finished
    }

    // MARK: - Envelope Creation

    /// Records the target method for this invocation.
    ///
    /// - Parameter target: The `RemoteCallTarget` representing the method to call.
    public mutating func recordTarget(_ target: RemoteCallTarget) {
        self.target = extractIdentifier(from: target)
    }

    /// Creates an `InvocationEnvelope` from the recorded state.
    ///
    /// - Parameters:
    ///   - recipientID: The ID of the target actor.
    ///   - senderID: Optional ID of the calling actor.
    /// - Returns: An `InvocationEnvelope` ready for transmission.
    /// - Throws: `RuntimeError` if the encoder state is invalid.
    public mutating func makeInvocationEnvelope(
        recipientID: String,
        senderID: String? = nil
    ) throws -> InvocationEnvelope {
        guard state == .finished else {
            throw RuntimeError.invalidState("Must call doneRecording() before creating envelope")
        }

        guard let target = target else {
            throw RuntimeError.invalidState("Target not recorded")
        }

        // Arguments are already individually encoded; pass them through as a list
        // so the bytes are not re-encoded when the envelope itself is serialized.
        let envelope = InvocationEnvelope(
            recipientID: recipientID,
            senderID: senderID,
            target: target,
            genericSubstitutions: genericSubstitutions,
            arguments: arguments,
            metadata: .init()
        )

        state = .consumed
        return envelope
    }

    // MARK: - Public Accessors

    /// Returns a read-only array of encoded arguments.
    ///
    /// This method allows access to the encoded arguments without exposing
    /// the internal mutable state. Useful for custom transport implementations
    /// that need to inspect argument data.
    ///
    /// - Returns: An array of `Data` representing each encoded argument.
    /// - Throws: `RuntimeError` if called before `doneRecording()`.
    public func encodedArguments() throws -> [Data] {
        guard state == .finished else {
            throw RuntimeError.invalidState("Must call doneRecording() before accessing arguments")
        }
        return arguments
    }

    // MARK: - Private Helpers

    /// Extracts the method identifier from a `RemoteCallTarget`.
    ///
    /// This uses the identifier property of the target which contains the mangled name.
    ///
    /// - Parameter target: The target to extract the identifier from.
    /// - Returns: A string identifier for the method.
    private func extractIdentifier(from target: RemoteCallTarget) -> String {
        // Use the identifier property directly - it contains the mangled name
        return target.identifier
    }
}

// MARK: - RuntimeError Extension

extension RuntimeError {
    /// Creates an invalid state error.
    static func invalidState(_ message: String) -> RuntimeError {
        .serializationFailed(message)
    }
}
