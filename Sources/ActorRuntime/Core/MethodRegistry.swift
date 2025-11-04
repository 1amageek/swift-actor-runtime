import Foundation
import Synchronization

/// Thread-safe registry for distributed method handlers
///
/// Maps method names to executable closures, bypassing Swift's lack of
/// public reflection APIs for distributed actor method invocation.
///
/// ## Design Rationale
///
/// Swift does not expose public APIs to execute distributed actor methods by name.
/// `DistributedActorSystem.executeDistributedTarget` delegates to internal
/// runtime APIs. MethodRegistry provides a workaround through manual registration.
///
/// ## Usage
///
/// ```swift
/// let registry = MethodRegistry()
///
/// // Actor registers its methods during initialization
/// distributed actor Sensor {
///     distributed func readTemperature() async -> Double { 22.5 }
///
///     func registerMethods(with registry: MethodRegistry) async {
///         await registry.register("readTemperature") { argsData in
///             let result = try await self.readTemperature()
///             return try JSONEncoder().encode(result)
///         }
///     }
/// }
///
/// // System executes method when RPC arrives
/// let resultData = try await registry.execute(
///     envelope.target,
///     arguments: envelope.arguments
/// )
/// ```
///
public final class MethodRegistry: Sendable {

    /// Method handler: takes serialized arguments, returns serialized result
    public typealias MethodHandler = @Sendable (Data) async throws -> Data

    /// Internal state protected by mutex
    private struct State {
        var methods: [String: MethodHandler] = [:]
    }

    /// Mutex-protected method storage
    private let mutex = Mutex(State())

    /// Initialize an empty registry
    public init() {}

    /// Register a method handler
    ///
    /// - Parameters:
    ///   - methodName: Method identifier (typically mangled Swift name)
    ///   - handler: Async closure that executes the method
    ///
    /// - Note: Registering the same method twice overwrites the previous handler
    ///
    public func register(_ methodName: String, handler: @escaping MethodHandler) {
        mutex.withLock { state in
            state.methods[methodName] = handler
        }
    }

    /// Execute a registered method
    ///
    /// - Parameters:
    ///   - methodName: Method identifier
    ///   - arguments: Serialized method arguments
    ///
    /// - Returns: Serialized method result
    /// - Throws: `RuntimeError.methodNotFound` if method not registered
    /// - Throws: `RuntimeError.executionFailed` if method execution throws
    ///
    public func execute(_ methodName: String, arguments: Data) async throws -> Data {
        let handler = mutex.withLock { state in
            state.methods[methodName]
        }

        guard let handler = handler else {
            throw RuntimeError.methodNotFound(methodName)
        }

        do {
            return try await handler(arguments)
        } catch let error as RuntimeError {
            // Preserve RuntimeError
            throw error
        } catch {
            // Wrap other errors
            throw RuntimeError.executionFailed(methodName, underlying: error.localizedDescription)
        }
    }

    /// Check if a method is registered
    ///
    /// - Parameter methodName: Method identifier
    /// - Returns: True if method is registered, false otherwise
    ///
    public func hasMethod(_ methodName: String) -> Bool {
        mutex.withLock { state in
            state.methods[methodName] != nil
        }
    }

    /// Unregister a method
    ///
    /// - Parameter methodName: Method identifier to remove
    ///
    /// - Note: Unregistering a non-existent method is a no-op
    ///
    public func unregister(_ methodName: String) {
        mutex.withLock { state in
            _ = state.methods.removeValue(forKey: methodName)
        }
    }

    /// Get all registered method names
    ///
    /// - Returns: Array of all registered method identifiers
    ///
    public func allMethods() -> [String] {
        mutex.withLock { state in
            Array(state.methods.keys)
        }
    }

    /// Clear all methods
    ///
    /// - Note: Typically used during system shutdown or testing
    ///
    public func clear() {
        mutex.withLock { state in
            state.methods.removeAll()
        }
    }

    /// Number of registered methods
    public var count: Int {
        mutex.withLock { state in
            state.methods.count
        }
    }
}
