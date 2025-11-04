import Foundation

/// Transport layer interface for distributed actor communication
///
/// All transport implementations (BLE, gRPC, WebSocket, etc.) must conform to this protocol.
/// The runtime handles invocation/response logic; transports handle connectivity.
///
/// ## Responsibilities
///
/// **Transport Layer**:
/// - Connection management
/// - Message delivery
/// - Fragmentation (if needed)
/// - Transport-specific optimizations
///
/// **Runtime Layer** (this package):
/// - Envelope creation/parsing
/// - Actor/method registry
/// - Serialization
///
/// ## Implementation Example
///
/// ```swift
/// import ActorRuntime
///
/// public final class BLETransport: DistributedTransport {
///     public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
///         let data = try JSONEncoder().encode(envelope)
///         // BLE-specific: fragment and send
///         try await writeBLECharacteristic(data)
///         return try await awaitBLEResponse(callID: envelope.callID)
///     }
///
///     public var incomingInvocations: AsyncStream<InvocationEnvelope> {
///         AsyncStream { continuation in
///             // Setup BLE delegate callbacks
///         }
///     }
///
///     public func sendResponse(_ envelope: ResponseEnvelope) async throws {
///         let data = try JSONEncoder().encode(envelope)
///         // BLE-specific: send via notification
///         try await notifyBLECharacteristic(data)
///     }
/// }
/// ```
///
public protocol DistributedTransport: Sendable {

    /// Send an invocation and await its response (client side)
    ///
    /// - Parameter envelope: The invocation to send
    /// - Returns: The response envelope
    /// - Throws: Transport-specific errors or `RuntimeError.timeout`
    ///
    /// ## Implementation Notes
    ///
    /// - This method should handle serialization and transport-specific delivery
    /// - Must await the corresponding response before returning
    /// - Should implement timeout handling
    /// - May fragment large messages if needed
    ///
    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope

    /// Stream of incoming invocations (server side)
    ///
    /// The transport listens for incoming RPC requests and yields them as they arrive.
    /// The runtime processes each invocation and sends responses via `sendResponse`.
    ///
    /// ## Implementation Notes
    ///
    /// - Should handle deserialization from transport format
    /// - May need to reassemble fragmented messages
    /// - Should be a long-lived stream for the lifetime of the transport
    ///
    var incomingInvocations: AsyncStream<InvocationEnvelope> { get }

    /// Send a response to an invocation (server side)
    ///
    /// - Parameter envelope: The response to send
    /// - Throws: Transport-specific errors
    ///
    /// ## Implementation Notes
    ///
    /// - Should handle serialization and transport-specific delivery
    /// - May fragment large messages if needed
    /// - Should match callID to route response to correct client
    ///
    func sendResponse(_ envelope: ResponseEnvelope) async throws

    /// Close the transport and cleanup resources
    ///
    /// - Throws: Cleanup errors (optional)
    ///
    /// ## Default Implementation
    ///
    /// A no-op default implementation is provided. Override if cleanup is needed.
    ///
    func close() async throws
}

/// Extension providing default implementations
extension DistributedTransport {
    /// Default close implementation (no-op)
    public func close() async throws {
        // Default: no cleanup needed
    }
}
