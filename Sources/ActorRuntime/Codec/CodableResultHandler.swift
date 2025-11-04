import Distributed
import Foundation

/// A Codable-based implementation of `DistributedTargetInvocationResultHandler`.
///
/// This handler captures the result of a distributed method execution and encodes it
/// into a `ResponseEnvelope` for transmission back to the caller.
///
/// ## Usage
///
/// ```swift
/// let handler = CodableResultHandler(callID: envelope.callID) { response in
///     try await transport.sendResponse(response)
/// }
///
/// try await executeDistributedTarget(
///     on: actor,
///     target: target,
///     invocationDecoder: &decoder,
///     handler: handler
/// )
/// ```
public struct CodableResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable

    private let callID: String
    private let sendResponse: (ResponseEnvelope) async throws -> Void

    /// Creates a result handler.
    ///
    /// - Parameters:
    ///   - callID: The call ID from the invocation envelope.
    ///   - sendResponse: Closure to send the response envelope back to the caller.
    public init(
        callID: String,
        sendResponse: @escaping (ResponseEnvelope) async throws -> Void
    ) {
        self.callID = callID
        self.sendResponse = sendResponse
    }

    // MARK: - DistributedTargetInvocationResultHandler

    public func onReturn<Success: Codable>(value: Success) async throws {
        let data = try JSONEncoder().encode(value)
        let envelope = ResponseEnvelope(
            callID: callID,
            result: .success(data),
            metadata: .init()
        )
        try await sendResponse(envelope)
    }

    public func onReturnVoid() async throws {
        let envelope = ResponseEnvelope(
            callID: callID,
            result: .void,
            metadata: .init()
        )
        try await sendResponse(envelope)
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        // Wrap user errors in RuntimeError for serialization
        let runtimeError: RuntimeError

        if let err = error as? RuntimeError {
            runtimeError = err
        } else {
            runtimeError = .executionFailed(
                String(describing: error),
                underlying: String(reflecting: error)
            )
        }

        let envelope = ResponseEnvelope(
            callID: callID,
            result: .failure(runtimeError),
            metadata: .init()
        )
        try await sendResponse(envelope)
    }
}
