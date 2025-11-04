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

import ActorRuntime
import Distributed
import Foundation
import Logging
import ServiceContextModule
import Metrics

/// The distributed actor system implementation for ActorEdge.
///
/// This system provides a gRPC-based distributed actor runtime
/// leveraging ActorRuntime's transport-agnostic primitives.
public final class ActorEdgeSystem: DistributedActorSystem, Sendable {
    public typealias ActorID = ActorEdgeID
    // Match ActorRuntime's serialization requirement (Codable only)
    // Note: Sendable is enforced by distributed actor isolation, not serialization
    public typealias SerializationRequirement = Codable

    // Use ActorRuntime's codec implementations
    public typealias InvocationEncoder = CodableInvocationEncoder
    public typealias InvocationDecoder = CodableInvocationDecoder
    public typealias ResultHandler = CodableResultHandler

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

    /// Transport layer (ActorRuntime's DistributedTransport)
    private let transport: DistributedTransport?

    /// Actor registry from ActorRuntime
    private let registry: ActorRuntime.ActorRegistry

    /// System configuration
    private let configuration: Configuration

    private let logger: Logger
    public let isServer: Bool

    /// Pre-assigned IDs for actors (thread-safe)
    private let preAssignedIDsStorage = PreAssignedIDStorage()

    // Metrics
    private let distributedCallsCounter: Counter
    private let methodInvocationsCounter: Counter
    private let metricNames: MetricNames

    /// Create a client-side actor system with a transport
    public init(transport: DistributedTransport, configuration: Configuration = .default) {
        self.transport = transport
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = false
        self.registry = ActorRuntime.ActorRegistry()

        // Initialize metrics
        self.metricNames = MetricNames(namespace: configuration.metrics.namespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
    }

    /// Create a server-side actor system without transport
    public init(configuration: Configuration = .default) {
        self.transport = nil
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = true
        self.registry = ActorRuntime.ActorRegistry()

        // Initialize metrics
        self.metricNames = MetricNames(namespace: configuration.metrics.namespace)
        self.distributedCallsCounter = Counter(label: metricNames.distributedCallsTotal)
        self.methodInvocationsCounter = Counter(label: metricNames.methodInvocationsTotal)
    }

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID {
        // Convert ActorEdgeID to String for ActorRuntime registry
        let actorIDString = id.description

        // Check if we have this actor locally
        if let actor = registry.find(id: actorIDString) {
            // Try to cast to the requested type
            guard let typedActor = actor as? Act else {
                throw RuntimeError.executionFailed(
                    "Actor type mismatch for \(id): expected \(Act.self), actual \(type(of: actor))",
                    underlying: "Type mismatch"
                )
            }
            return typedActor
        }

        // If not found locally, return nil to let the runtime create a remote proxy
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

        // Register actor in ActorRuntime registry
        if let actorID = actor.id as? ActorEdgeID {
            registry.register(actor, id: actorID.description)
        }
    }

    public func resignID(_ id: ActorID) {
        logger.debug("Actor resigned", metadata: [
            "actorID": "\(id)"
        ])

        // Unregister actor from registry
        registry.unregister(id: id.description)
    }

    public func makeInvocationEncoder() -> InvocationEncoder {
        CodableInvocationEncoder()
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
            throw RuntimeError.transportFailed("No transport configured")
        }

        // Update metrics
        distributedCallsCounter.increment()

        // Create InvocationEnvelope from encoder
        // Note: actor.id is already ActorEdgeID since Act.ID == ActorID
        let invocationEnvelope = try invocation.makeInvocationEnvelope(
            recipientID: actor.id.description,
            senderID: nil
        )

        // Send through transport and get response
        let responseEnvelope = try await transport.sendInvocation(invocationEnvelope)

        // Extract result from response
        switch responseEnvelope.result {
        case .success(let data):
            // Deserialize the result
            let decoder = JSONDecoder()
            return try decoder.decode(Res.self, from: data)

        case .void:
            throw RuntimeError.executionFailed(
                "Unexpected void response for non-void call",
                underlying: "Protocol mismatch"
            )

        case .failure(let error):
            // Re-throw the remote error
            throw RuntimeError.executionFailed(
                "Remote call failed: \(error)",
                underlying: "\(error)"
            )
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
            throw RuntimeError.transportFailed("No transport configured")
        }

        // Update metrics
        distributedCallsCounter.increment()

        // Create InvocationEnvelope from encoder
        // Note: actor.id is already ActorEdgeID since Act.ID == ActorID
        let invocationEnvelope = try invocation.makeInvocationEnvelope(
            recipientID: actor.id.description,
            senderID: nil
        )

        // Send through transport and get response
        let responseEnvelope = try await transport.sendInvocation(invocationEnvelope)

        // Extract result from response
        switch responseEnvelope.result {
        case .void:
            // Expected for void return
            return

        case .success(_):
            throw RuntimeError.executionFailed(
                "Unexpected non-void response for void call",
                underlying: "Protocol mismatch"
            )

        case .failure(let error):
            // Re-throw the remote error
            throw RuntimeError.executionFailed(
                "Remote call failed: \(error)",
                underlying: "\(error)"
            )
        }
    }

    // MARK: - Server-side Actor Management

    /// Find an actor by ID
    public func findActor(id: ActorEdgeID) -> (any DistributedActor)? {
        return registry.find(id: id.description)
    }

    /// Get the ActorRuntime registry (for server integration)
    public func getRegistry() -> ActorRuntime.ActorRegistry {
        return registry
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
