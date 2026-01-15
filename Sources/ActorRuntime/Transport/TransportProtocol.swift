import Foundation

/// Transport layer interface for distributed actor communication
///
/// All transport implementations (gRPC, WebSocket, BLE, etc.) must conform to this protocol.
/// The protocol supports symmetric bidirectional communication where both peers can
/// send invocations and responses.
///
/// ## Overview
///
/// `DistributedTransport` abstracts the underlying communication mechanism,
/// allowing distributed actors to communicate over any transport layer.
/// Implementations handle connection management, serialization, and message delivery.
///
/// The transport lifecycle follows a simple pattern:
/// 1. Create the transport instance
/// 2. Call ``start()`` to initialize connections
/// 3. Use ``send(_:)`` and ``messages`` for communication
/// 4. Call ``stop()`` to cleanup resources
///
/// ## Usage
///
/// ```swift
/// let transport = GRPCTransport(port: 50051)
/// try await transport.start()
///
/// // Send messages
/// try await transport.send(.invocation(envelope))
/// try await transport.send(.response(response))
///
/// // Receive messages
/// for try await envelope in transport.messages {
///     switch envelope {
///     case .invocation(let inv):
///         // Handle incoming method call
///     case .response(let res):
///         // Handle response to a previous call
///     }
/// }
///
/// // Cleanup
/// await transport.stop()
/// ```
///
/// ## Implementing a Transport
///
/// When implementing this protocol:
/// - ``start()`` should establish connections and prepare for communication
/// - ``send(_:)`` should serialize and deliver the envelope reliably
/// - ``messages`` should yield envelopes as they arrive
/// - ``stop()`` should close connections and release resources
///
public protocol DistributedTransport: Sendable {

    /// Starts the transport and prepares for communication.
    ///
    /// This method initializes the transport layer. Depending on the implementation:
    /// - **Server mode**: Binds to a port and starts accepting connections
    /// - **Client mode**: Establishes a connection to the remote peer
    ///
    /// - Throws: Transport-specific errors if initialization fails
    ///   (e.g., port already in use, connection refused).
    func start() async throws

    /// Sends an envelope to the remote peer.
    ///
    /// Both invocations and responses can be sent using this method,
    /// enabling symmetric bidirectional communication.
    ///
    /// - Parameter envelope: The envelope to send (invocation or response).
    /// - Throws: Transport-specific errors if sending fails
    ///   (e.g., connection lost, serialization error).
    func send(_ envelope: Envelope) async throws

    /// A stream of incoming envelopes from remote peers.
    ///
    /// This stream yields both invocations and responses as they arrive.
    /// Use pattern matching to handle each message type appropriately.
    ///
    /// The stream throws errors for transport-level failures such as
    /// connection loss or deserialization errors.
    var messages: AsyncThrowingStream<Envelope, Error> { get }

    /// Stops the transport and releases all resources.
    ///
    /// This method should:
    /// - Close all active connections
    /// - Cancel any pending operations
    /// - Release system resources (sockets, file handles, etc.)
    ///
    /// After calling this method, the transport should not be reused.
    func stop() async
}
