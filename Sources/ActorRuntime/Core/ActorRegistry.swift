#if canImport(Distributed)
import Distributed
import Synchronization

/// Thread-safe registry for distributed actor instances
///
/// Maps actor identifiers to their local instances, enabling invocation routing.
/// Each ActorSystem implementation should maintain its own registry.
///
/// ## Thread Safety
///
/// All methods are thread-safe via Mutex, safe for concurrent access from
/// multiple transport connections.
///
/// ## Memory Management
///
/// **Important**: ActorRegistry maintains **strong references** to registered actors.
/// You must explicitly call `unregister(id:)` when an actor is no longer needed
/// to prevent memory leaks.
///
/// ```swift
/// // Register actor
/// registry.register(sensor, id: "sensor-1")
///
/// // When done, unregister to allow deallocation
/// registry.unregister(id: "sensor-1")
///
/// // Or clear all actors during shutdown
/// registry.clear()
/// ```
///
/// Failure to unregister actors can cause memory leaks in long-running systems.
/// Consider implementing cleanup logic in your transport's `close()` method.
///
/// ## Usage
///
/// ```swift
/// let registry = ActorRegistry()
///
/// // Server side: register local actors
/// registry.register(sensor, id: "sensor-1")
///
/// // Handle incoming RPC
/// if let actor = registry.find(id: envelope.recipientID) {
///     // Execute method on actor
/// }
///
/// // Cleanup when actor is no longer needed
/// registry.unregister(id: "sensor-1")
/// ```
///
public final class ActorRegistry: Sendable {

    /// Internal state protected by mutex
    private struct State {
        var actors: [String: any DistributedActor] = [:]
    }

    /// Mutex-protected actor storage
    private let mutex = Mutex(State())

    /// Initialize an empty registry
    public init() {}

    /// Register a distributed actor instance
    ///
    /// - Parameters:
    ///   - actor: The actor instance to register
    ///   - id: Unique identifier for this actor
    ///
    /// - Note: Registering the same ID twice overwrites the previous actor
    ///
    public func register(_ actor: any DistributedActor, id: String) {
        mutex.withLock { state in
            state.actors[id] = actor
        }
    }

    /// Find a registered actor by ID
    ///
    /// - Parameter id: The actor identifier
    /// - Returns: The actor instance if found, nil otherwise
    ///
    /// - Complexity: O(1) dictionary lookup
    ///
    public func find(id: String) -> (any DistributedActor)? {
        mutex.withLock { state in
            state.actors[id]
        }
    }

    /// Unregister an actor
    ///
    /// - Parameter id: The actor identifier to remove
    ///
    /// - Note: Unregistering a non-existent ID is a no-op
    ///
    public func unregister(id: String) {
        // Remove from dictionary while holding lock,
        // then release actor outside the lock to avoid recursive lock
        // if actor deinit calls resignID()
        let actorToRelease = mutex.withLock { state -> (any DistributedActor)? in
            state.actors.removeValue(forKey: id)
        }
        // Ensure actor is released after this point, safely outside the lock
        withExtendedLifetime(actorToRelease) { _ in }
    }

    /// Get all registered actor IDs
    ///
    /// - Returns: Array of all registered identifiers
    ///
    public func allActorIDs() -> [String] {
        mutex.withLock { state in
            Array(state.actors.keys)
        }
    }

    /// Clear all registered actors
    ///
    /// - Note: Typically used during system shutdown or testing
    ///
    public func clear() {
        // Extract actors from dictionary while holding lock,
        // then release them outside the lock to avoid recursive lock
        // if actor deinit calls resignID()
        //
        // IMPORTANT: We use a two-phase approach to ensure actors are released
        // outside the lock even with aggressive compiler optimizations:
        // 1. Swap with empty dictionary (actors moved out atomically)
        // 2. Release actors after lock is released
        var actorsToRelease: [String: any DistributedActor] = [:]
        mutex.withLock { state in
            swap(&actorsToRelease, &state.actors)
        }
        // actorsToRelease now holds all actors and will be deallocated
        // after this scope, safely outside the lock
        withExtendedLifetime(actorsToRelease) { _ in }
    }

    /// Number of registered actors
    public var count: Int {
        mutex.withLock { state in
            state.actors.count
        }
    }
}
#endif
