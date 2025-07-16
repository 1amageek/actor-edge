import Foundation
import ServiceContextModule

/// Protocol for network transports that can send distributed actor calls
public protocol ActorTransport: Sendable {
    /// Execute a remote call that returns a value
    func remoteCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> Data
    
    /// Execute a remote call that returns void
    func remoteCallVoid(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws
    
    /// Execute a streaming remote call
    func streamCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> AsyncThrowingStream<Data, Error>
}