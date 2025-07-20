import Foundation
import Distributed

/// Registry for managing distributed actors on the server side
/// This is a synchronous class with thread-safe operations as required by DistributedActorSystem
public final class ActorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var actors: [ActorEdgeID: any DistributedActor] = [:]
    
    public init() {}
    
    /// Register an actor with the registry
    public func register(_ actor: any DistributedActor, id: ActorEdgeID) {
        lock.lock()
        defer { lock.unlock() }
        actors[id] = actor
    }
    
    /// Unregister an actor from the registry
    public func unregister(id: ActorEdgeID) {
        lock.lock()
        defer { lock.unlock() }
        actors.removeValue(forKey: id)
    }
    
    /// Find an actor by ID
    public func find(id: ActorEdgeID) -> (any DistributedActor)? {
        lock.lock()
        defer { lock.unlock() }
        return actors[id]
    }
    
    /// Get all registered actor IDs
    public func allActorIDs() -> [ActorEdgeID] {
        lock.lock()
        defer { lock.unlock() }
        return Array(actors.keys)
    }
    
    /// Clear all registered actors
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        actors.removeAll()
    }
}