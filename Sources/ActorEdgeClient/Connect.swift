import Foundation
import ActorEdgeCore
import Distributed

/// Convenience methods for connecting to ActorEdge servers
public extension ActorEdgeSystem {
    /// Create a client system connected to the specified endpoint
    static func client(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil
    ) async throws -> ActorEdgeSystem {
        let transport = try await GRPCActorTransport(endpoint, tls: tls)
        return ActorEdgeSystem(transport: transport)
    }
}

/// Convenience methods for resolving distributed actors
public extension DistributedActor where ActorSystem == ActorEdgeSystem {
    /// Resolve a distributed actor with a string ID
    static func resolve(
        id: String,
        using system: ActorEdgeSystem
    ) throws -> Self {
        try system.resolve(id: ActorEdgeID(id), as: Self.self)!
    }
    
    /// Resolve a distributed actor with a known ID
    static func resolve(
        id: ActorEdgeID,
        using system: ActorEdgeSystem
    ) throws -> Self {
        try system.resolve(id: id, as: Self.self)!
    }
}