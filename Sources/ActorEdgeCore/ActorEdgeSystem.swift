import Distributed
import Foundation
import Logging
import ServiceContextModule
import Metrics

/// The distributed actor system implementation for ActorEdge
public final class ActorEdgeSystem: DistributedActorSystem {
    public typealias ActorID = ActorEdgeID
    public typealias SerializationRequirement = Codable & Sendable
    public typealias InvocationEncoder = ActorEdgeInvocationEncoder
    public typealias InvocationDecoder = ActorEdgeInvocationDecoder
    public typealias ResultHandler = ActorEdgeResultHandler
    
    private let transport: (any ActorTransport)?
    private let logger: Logger
    public let isServer: Bool
    public let registry: ActorRegistry?
    
    /// The serialization system for this actor system
    public let serialization: Serialization
    
    // Metrics
    private let distributedCallsCounter: Counter
    private let methodInvocationsCounter: Counter
    private let metricNames: MetricNames
    
    /// Create a client-side actor system with a transport
    public init(transport: any ActorTransport, metricsNamespace: String = "actor_edge") {
        self.transport = transport
        self.logger = Logger(label: "ActorEdge.System")
        self.isServer = false
        self.registry = nil
        // Initialize serialization
        self.serialization = Serialization()
        
        // Initialize metrics
        self.metricNames = MetricNames(namespace: metricsNamespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
    }
    
    /// Create a server-side actor system without transport
    public init(metricsNamespace: String = "actor_edge") {
        self.transport = nil
        self.logger = Logger(label: "ActorEdge.System")
        self.isServer = true
        self.registry = ActorRegistry()
        // Initialize serialization
        self.serialization = Serialization()
        
        // Initialize metrics
        self.metricNames = MetricNames(namespace: metricsNamespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
    }
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? 
        where Act: DistributedActor, Act.ID == ActorID {
        // On the client side, return nil to let the runtime create a remote proxy
        // The runtime will use the generated $Protocol stub which knows how to
        // forward calls through our remoteCall methods
        guard isServer else {
            return nil
        }
        
        // On the server side, we don't support resolving actors by ID
        // Actors are registered when they're created via actorReady()
        // For now, throw an error as we don't support actor lookups
        throw ActorEdgeError.actorNotFound(id)
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
        
        // Register actor if on server side
        if isServer, let registry = registry {
            // Check if the actor's ID type is ActorEdgeID
            if let actorID = actor.id as? ActorEdgeID {
                Task {
                    await registry.register(actor, id: actorID)
                }
            }
        }
    }
    
    public func resignID(_ id: ActorID) {
        logger.debug("Actor resigned", metadata: [
            "actorID": "\(id)"
        ])
        
        // Unregister actor if on server side
        if isServer, let registry = registry {
            Task {
                await registry.unregister(id: id)
            }
        }
    }
    
    public func makeInvocationEncoder() -> InvocationEncoder {
        ActorEdgeInvocationEncoder(system: self)
    }
    
    // MARK: - Remote Call Execution
    
    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: Distributed.RemoteCallTarget,
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
        
        // Update metrics
        distributedCallsCounter.increment()
        
        // Check if doneRecording() has already been called
        if invocation.state == .recording {
            try invocation.doneRecording()
        }
        
        // Create InvocationMessage for modern approach
        let encoder = invocation
        
        let message = try encoder.createInvocationMessage(targetIdentifier: target.identifier)
        let messageBuffer = try serialization.serialize(message, system: self)
        let messageData = messageBuffer.readData()
        
        let context = ServiceContext.current ?? ServiceContext.topLevel
        
        let resultData = try await transport.remoteCall(
            on: actor.id,
            method: target.identifier,
            arguments: messageData,
            context: context
        )
        
        let buffer = Serialization.Buffer.data(resultData)
        return try serialization.deserialize(buffer, as: Res.self, system: self)
    }
    
    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: Distributed.RemoteCallTarget,
        invocation: inout InvocationEncoder,
        throwing: Err.Type
    ) async throws
    where Act: DistributedActor,
          Act.ID == ActorID,
          Err: Error {
        guard let transport = transport else {
            throw ActorEdgeError.transportError("No transport configured")
        }
        
        // Update metrics
        distributedCallsCounter.increment()
        
        // Check if doneRecording() has already been called
        if invocation.state == .recording {
            try invocation.doneRecording()
        }
        
        // Create InvocationMessage for modern approach
        let encoder = invocation
        
        let message = try encoder.createInvocationMessage(targetIdentifier: target.identifier)
        let messageBuffer = try serialization.serialize(message, system: self)
        let messageData = messageBuffer.readData()
        
        let context = ServiceContext.current ?? ServiceContext.topLevel
        
        try await transport.remoteCallVoid(
            on: actor.id,
            method: target.identifier,
            arguments: messageData,
            context: context
        )
    }
    
    // MARK: - Server-side Actor Management
    
    /// Find an actor by ID (server-side only)
    public func findActor(id: ActorID) async -> (any DistributedActor)? {
        guard isServer, let registry = registry else {
            return nil
        }
        return await registry.find(id: id)
    }
    
}