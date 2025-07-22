//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Distributed
import Foundation
import Logging
import ServiceContextModule
import Metrics

/// The distributed actor system implementation for ActorEdge.
///
/// This system provides a protocol-independent distributed actor runtime
/// that can work with any transport layer (gRPC, TCP, etc.).
public final class ActorEdgeSystem: DistributedActorSystem, Sendable {
    public typealias ActorID = ActorEdgeID
    public typealias SerializationRequirement = Codable & Sendable
    public typealias InvocationEncoder = ActorEdgeInvocationEncoder
    public typealias InvocationDecoder = ActorEdgeInvocationDecoder
    public typealias ResultHandler = ActorEdgeResultHandler
    
    /// Configuration for ActorEdgeSystem
    public struct Configuration: Sendable {
        /// Metrics configuration
        public let metrics: MetricsConfiguration
        
        /// Tracing configuration
        public let tracing: TracingConfiguration
        
        /// Request timeout
        public let timeout: TimeInterval
        
        /// Maximum retry attempts
        public let maxRetries: Int
        
        /// Logger label
        public let loggerLabel: String
        
        public init(
            metrics: MetricsConfiguration = .default,
            tracing: TracingConfiguration = .disabled,
            timeout: TimeInterval = 30,
            maxRetries: Int = 3,
            loggerLabel: String = "ActorEdge.System"
        ) {
            self.metrics = metrics
            self.tracing = tracing
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.loggerLabel = loggerLabel
        }
        
        /// Default configuration
        public static let `default` = Configuration()
    }
    
    /// Protocol-independent transport layer
    private let transport: MessageTransport?
    
    /// Invocation processor for envelope handling
    private let invocationProcessor: DistributedInvocationProcessor
    
    /// System configuration
    private let configuration: Configuration
    
    private let logger: Logger
    public let isServer: Bool
    public let registry: ActorRegistry?
    
    /// The serialization system for this actor system
    public let serialization: SerializationSystem
    
    /// Pre-assigned IDs for actors (thread-safe)
    private let preAssignedIDsStorage = PreAssignedIDStorage()
    
    // Metrics
    private let distributedCallsCounter: Counter
    private let methodInvocationsCounter: Counter
    private let metricNames: MetricNames
    
    /// Create a client-side actor system with a transport
    public init(transport: MessageTransport, configuration: Configuration = .default) {
        self.transport = transport
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = false
        self.registry = ActorRegistry() // Clients can also have local actors
        self.serialization = SerializationSystem()
        
        // Initialize metrics first
        self.metricNames = MetricNames(namespace: configuration.metrics.namespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
        
        // Initialize invocation processor after all other properties
        self.invocationProcessor = DistributedInvocationProcessor(serialization: self.serialization)
    }
    
    /// Create a server-side actor system without transport
    public init(configuration: Configuration = .default) {
        self.transport = nil
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = true
        self.registry = ActorRegistry()
        self.serialization = SerializationSystem()
        
        // Initialize metrics first
        self.metricNames = MetricNames(namespace: configuration.metrics.namespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
        
        // Initialize invocation processor after all other properties
        self.invocationProcessor = DistributedInvocationProcessor(serialization: self.serialization)
    }
    
    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? 
        where Act: DistributedActor, Act.ID == ActorID {
        // First check if we have this actor locally (both client and server can have local actors)
        if let registry = registry {
            if let actor = registry.find(id: id) {
                // Try to cast to the requested type
                guard let typedActor = actor as? Act else {
                    throw ActorEdgeError.actorTypeMismatch(id, expected: "\(Act.self)", actual: "\(type(of: actor))")
                }
                return typedActor
            }
        }
        
        // If not found locally, return nil to let the runtime create a remote proxy
        // This allows the @Resolvable macro to generate the appropriate stub
        return nil
    }
    
    public func assignID<Act>(_ actorType: Act.Type) -> ActorID 
        where Act: DistributedActor {
        // Check if we have a pre-assigned ID for this actor type
        if let preAssignedID = preAssignedIDsStorage.getNext() {
            return ActorEdgeID(preAssignedID)
        }
        // Otherwise, generate a new ID
        return ActorEdgeID()
    }
    
    /// Sets pre-assigned IDs for actors
    public func setPreAssignedIDs(_ ids: [String]) {
        preAssignedIDsStorage.setIDs(ids)
    }
    
    public func actorReady<Act>(_ actor: Act) 
        where Act: DistributedActor {
        logger.info("Actor ready", metadata: [
            "actorType": "\(Act.self)",
            "actorID": "\(actor.id)"
        ])
        
        // Register actor in registry if available (both client and server can have actors)
        if let registry = registry {
            // Check if the actor's ID type is ActorEdgeID
            if let actorID = actor.id as? ActorEdgeID {
                registry.register(actor, id: actorID)
            }
        }
    }
    
    public func resignID(_ id: ActorID) {
        logger.debug("Actor resigned", metadata: [
            "actorID": "\(id)"
        ])
        
        // Unregister actor from registry if available
        if let registry = registry {
            registry.unregister(id: id)
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
        
        // Ensure invocation is finalized
        if invocation.state == .recording {
            try invocation.doneRecording()
        }
        
        // Create envelope from invocation
        let envelope = try invocationProcessor.createInvocationEnvelope(
            recipient: actor.id,
            target: target,
            encoder: invocation,
            traceContext: ServiceContext.current?.baggage ?? [:]
        )
        
        // Send envelope and wait for response
        guard let responseEnvelope = try await transport.send(envelope) else {
            throw ActorEdgeError.transportError("No response received")
        }
        
        // Extract result from response
        let result = try invocationProcessor.extractResult(from: responseEnvelope)
        
        switch result {
        case .success(let serialized):
            return try serialization.deserialize(serialized, as: Res.self)
        case .void:
            throw ActorEdgeError.invocationError("Unexpected void response for non-void call")
        case .error(let serializedError):
            // Try to deserialize the error
            if throwing == Never.self {
                throw ActorEdgeError.invocationError("Unexpected error for non-throwing call")
            }
            throw ActorEdgeError.remoteCallError(serializedError.message)
        }
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
        
        // Ensure invocation is finalized
        if invocation.state == .recording {
            try invocation.doneRecording()
        }
        
        // Create envelope from invocation
        let envelope = try invocationProcessor.createInvocationEnvelope(
            recipient: actor.id,
            target: target,
            encoder: invocation,
            traceContext: ServiceContext.current?.baggage ?? [:]
        )
        
        // Send envelope and wait for response
        guard let responseEnvelope = try await transport.send(envelope) else {
            throw ActorEdgeError.transportError("No response received")
        }
        
        // Extract result from response
        let result = try invocationProcessor.extractResult(from: responseEnvelope)
        
        switch result {
        case .void:
            // Expected for void return
            return
        case .success(_):
            throw ActorEdgeError.invocationError("Unexpected non-void response for void call")
        case .error(let serializedError):
            // Try to deserialize the error
            if throwing == Never.self {
                throw ActorEdgeError.invocationError("Unexpected error for non-throwing call")
            }
            throw ActorEdgeError.remoteCallError(serializedError.message)
        }
    }
    
    // MARK: - Server-side Actor Management
    
    /// Find an actor by ID
    public func findActor(id: ActorID) -> (any DistributedActor)? {
        guard let registry = registry else {
            return nil
        }
        return registry.find(id: id)
    }
    
    // MARK: - Logging
    
    /// Log a message (internal use)
    internal func log(_ message: String, level: Logger.Level = .debug) {
        logger.log(level: level, "\(message)")
    }
}

// MARK: - Service Context Extension

extension ServiceContext {
    /// Extract baggage as a dictionary for trace context
    var baggage: [String: String] {
        // This is a placeholder implementation
        // ServiceContext doesn't provide a way to iterate through all keys
        // In a real implementation, you would need to:
        // 1. Use a custom baggage type that tracks all key-value pairs
        // 2. Or maintain a registry of known context keys
        // 3. Or use the distributed tracing baggage APIs
        
        // For now, return empty dictionary
        // Tests should be updated to not rely on automatic context propagation
        return [:]
    }
}

// MARK: - Pre-assigned ID Storage

/// Thread-safe storage for pre-assigned actor IDs
private final class PreAssignedIDStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    
    func setIDs(_ newIDs: [String]) {
        lock.lock()
        defer { lock.unlock() }
        ids = newIDs
    }
    
    func getNext() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return ids.isEmpty ? nil : ids.removeFirst()
    }
}