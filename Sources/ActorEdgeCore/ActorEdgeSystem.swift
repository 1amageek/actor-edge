import Distributed
import Foundation
import Logging
import ServiceContextModule

/// The distributed actor system implementation for ActorEdge
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public final class ActorEdgeSystem: DistributedActorSystem {
    public typealias ActorID = ActorEdgeID
    public typealias SerializationRequirement = ActorEdgeSerializable
    public typealias InvocationEncoder = ActorEdgeInvocationEncoder
    public typealias InvocationDecoder = ActorEdgeInvocationDecoder
    public typealias ResultHandler = ActorEdgeResultHandler
    
    private let transport: (any ActorTransport)?
    private let logger: Logger
    private let isServer: Bool
    
    /// Create a client-side actor system with a transport
    public init(transport: any ActorTransport) {
        self.transport = transport
        self.logger = Logger(label: "ActorEdge.System")
        self.isServer = false
    }
    
    /// Create a server-side actor system without transport
    public init() {
        self.transport = nil
        self.logger = Logger(label: "ActorEdge.System")
        self.isServer = true
    }
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? 
        where Act: DistributedActor, Act.ID == ActorID {
        guard !isServer else {
            throw ActorEdgeError.actorNotFound(id)
        }
        
        // Create a proxy actor that forwards calls through transport
        // This will be implemented when we have the proxy generation logic
        fatalError("Proxy actor creation not yet implemented")
    }
    
    public func assignID<Act>(_ actorType: Act.Type) -> ActorID 
        where Act: DistributedActor {
        ActorEdgeID()
    }
    
    public func actorReady<Act>(_ actor: Act) 
        where Act: DistributedActor {
        logger.info("Actor ready", metadata: [
            "actorType": "\(Act.self)",
            "actorID": "\(actor.id)"
        ])
    }
    
    public func resignID(_ id: ActorID) {
        logger.debug("Actor resigned", metadata: [
            "actorID": "\(id)"
        ])
    }
    
    public func makeInvocationEncoder() -> InvocationEncoder {
        ActorEdgeInvocationEncoder()
    }
    
    // MARK: - Remote Call Execution
    
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error,
          Res: SerializationRequirement {
        guard let transport = transport else {
            throw ActorEdgeError.transportError("No transport configured")
        }
        
        try invocation.doneRecording()
        let arguments = try invocation.getEncodedData()
        let context = ServiceContext.current ?? ServiceContext.topLevel
        
        let resultData = try await transport.remoteCall(
            on: actor.id,
            method: target.identifier,
            arguments: arguments,
            context: context
        )
        
        // Decode the result
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(Res.self, from: resultData)
    }
    
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {
        guard let transport = transport else {
            throw ActorEdgeError.transportError("No transport configured")
        }
        
        try invocation.doneRecording()
        let arguments = try invocation.getEncodedData()
        let context = ServiceContext.current ?? ServiceContext.topLevel
        
        try await transport.remoteCallVoid(
            on: actor.id,
            method: target.identifier,
            arguments: arguments,
            context: context
        )
    }
    
    // MARK: - Server-side Execution
    
    /// Execute a distributed target on the server side
    public func executeDistributedTarget<Act>(
        on actor: Act,
        target: RemoteCallTarget,
        invocationDecoder: inout InvocationDecoder,
        handler: ResultHandler
    ) async throws -> Data
    where Act: DistributedActor, Act.ID == ActorID {
        // This is called on the server side to execute the actual method
        // The implementation depends on Swift runtime support
        // For now, we'll throw an error indicating this needs runtime support
        throw ActorEdgeError.methodNotFound(target.identifier)
    }
    
    // MARK: - Protocol Requirements
    
    public func invokeHandlerOnReturn(
        handler: ResultHandler,
        resultBuffer: UnsafeRawPointer,
        metatype: any Any.Type
    ) async throws {
        // This is used by the runtime to invoke the result handler
        // For now, this is a stub implementation
        fatalError("invokeHandlerOnReturn not yet implemented")
    }
}