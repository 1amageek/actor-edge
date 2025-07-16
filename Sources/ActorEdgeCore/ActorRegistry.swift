import Foundation
import Distributed

/// Registry for managing distributed actors on the server side
public actor ActorRegistry {
    private var actors: [ActorEdgeID: any DistributedActor] = [:]
    
    /// Register an actor with the registry
    public func register(_ actor: any DistributedActor, id: ActorEdgeID) {
        actors[id] = actor
    }
    
    /// Unregister an actor from the registry
    public func unregister(id: ActorEdgeID) {
        actors.removeValue(forKey: id)
    }
    
    /// Find an actor by ID
    public func find(id: ActorEdgeID) -> (any DistributedActor)? {
        return actors[id]
    }
    
    /// Get all registered actor IDs
    public func allActorIDs() -> [ActorEdgeID] {
        return Array(actors.keys)
    }
    
    /// Clear all registered actors
    public func clear() {
        actors.removeAll()
    }
}