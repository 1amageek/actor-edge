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

        /// Request timeout
        public let timeout: TimeInterval

        /// Maximum retry attempts
        public let maxRetries: Int

        /// Logger label
        public let loggerLabel: String

        public init(
            metrics: MetricsConfiguration = .default,
            timeout: TimeInterval = 30,
            maxRetries: Int = 3,
            loggerLabel: String = "ActorEdge.System"
        ) {
            self.metrics = metrics
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
    private let actorRegistrationsCounter: Counter
    private let actorResolutionsCounter: Counter
    private let metricNames: MetricNames

    /// Create a client-side actor system with a transport
    public init(transport: DistributedTransport, configuration: Configuration = .default) {
        self.transport = transport
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = false
        self.registry = ActorRuntime.ActorRegistry()

        // Initialize metrics
        let (names, distCalls, actorReg, actorRes) = Self.initializeMetrics(configuration)
        self.metricNames = names
        self.distributedCallsCounter = distCalls
        self.actorRegistrationsCounter = actorReg
        self.actorResolutionsCounter = actorRes
    }

    /// Create a server-side actor system without transport
    public init(configuration: Configuration = .default) {
        self.transport = nil
        self.configuration = configuration
        self.logger = Logger(label: configuration.loggerLabel)
        self.isServer = true
        self.registry = ActorRuntime.ActorRegistry()

        // Initialize metrics
        let (names, distCalls, actorReg, actorRes) = Self.initializeMetrics(configuration)
        self.metricNames = names
        self.distributedCallsCounter = distCalls
        self.actorRegistrationsCounter = actorReg
        self.actorResolutionsCounter = actorRes
    }

    // MARK: - Private Helpers

    /// Initialize metrics counters for the actor system
    private static func initializeMetrics(_ configuration: Configuration) -> (MetricNames, Counter, Counter, Counter) {
        let metricNames = MetricNames(namespace: configuration.metrics.namespace)
        return (
            metricNames,
            Counter(label: metricNames.distributedCallsTotal),
            Counter(label: metricNames.actorRegistrationsTotal),
            Counter(label: metricNames.actorResolutionsTotal)
        )
    }

    public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act?
        where Act: DistributedActor, Act.ID == ActorID {
        // Update metrics
        actorResolutionsCounter.increment()

        // Convert ActorEdgeID to String for ActorRuntime registry
        let actorIDString = id.description

        // Check if we have this actor locally
        if let actor = registry.find(id: actorIDString) {
            // Try to cast to the requested type
            if let typedActor = actor as? Act {
                // Direct type match - return the actor
                return typedActor
            }

            // For @Resolvable protocol stubs ($Protocol), the actor may be the concrete
            // implementation type (e.g., TestActorImpl) rather than the stub type ($TestActor).
            // In this case, return nil to let Swift runtime create the appropriate stub/proxy.
            // The runtime will forward calls to this local actor through remoteCall.
            logger.trace(
                "Actor found but type differs",
                metadata: [
                    "actorID": "\(id)",
                    "requestedType": "\(Act.self)",
                    "actualType": "\(type(of: actor))"
                ]
            )
            return nil
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

        // Update metrics
        actorRegistrationsCounter.increment()

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

        // Update metrics
        distributedCallsCounter.increment()

        // Check if we have a local actor for this ID
        if let localActor = registry.find(id: actor.id.description) {
            // Local execution: call the actor directly using executeDistributedTarget
            logger.trace("Executing local call", metadata: ["actorID": "\(actor.id)", "target": "\(target.identifier)"])

            // Record target (it's passed as parameter, not yet in encoder)
            invocation.recordTarget(target)

            // Create InvocationEnvelope from encoder
            let invocationEnvelope = try invocation.makeInvocationEnvelope(
                recipientID: actor.id.description,
                senderID: nil
            )

            // Create decoder from envelope
            var decoder = try CodableInvocationDecoder(envelope: invocationEnvelope)

            // Capture the response
            var capturedResponse: ResponseEnvelope?

            // Create result handler with send closure
            let handler = CodableResultHandler(
                callID: invocationEnvelope.callID,
                sendResponse: { response in
                    capturedResponse = response
                }
            )

            // Execute the distributed target on the local actor
            try await executeDistributedTarget(
                on: localActor,
                target: target,
                invocationDecoder: &decoder,
                handler: handler
            )

            // Get the captured response
            guard let responseEnvelope = capturedResponse else {
                throw RuntimeError.executionFailed(
                    "No response captured from local actor execution",
                    underlying: "Internal error"
                )
            }

            // Extract and return result
            switch responseEnvelope.result {
            case .success(let data):
                let decoder = JSONDecoder()
                return try decoder.decode(Res.self, from: data)

            case .void:
                throw RuntimeError.executionFailed(
                    "Unexpected void response for non-void call",
                    underlying: "Protocol mismatch"
                )

            case .failure(let error):
                throw error
            }
        }

        // Remote execution: require transport
        guard let transport = transport else {
            throw RuntimeError.transportFailed("No transport configured")
        }

        // Record target (it's passed as parameter, not yet in encoder)
        invocation.recordTarget(target)

        // Create InvocationEnvelope from encoder
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
            // Re-throw the remote error directly to preserve error type information
            throw error
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

        // Update metrics
        distributedCallsCounter.increment()

        // Check if we have a local actor for this ID
        if let localActor = registry.find(id: actor.id.description) {
            // Local execution: call the actor directly using executeDistributedTarget
            logger.trace("Executing local void call", metadata: ["actorID": "\(actor.id)", "target": "\(target.identifier)"])

            // Record target (it's passed as parameter, not yet in encoder)
            invocation.recordTarget(target)

            // Create InvocationEnvelope from encoder
            let invocationEnvelope = try invocation.makeInvocationEnvelope(
                recipientID: actor.id.description,
                senderID: nil
            )

            // Create decoder from envelope
            var decoder = try CodableInvocationDecoder(envelope: invocationEnvelope)

            // Capture the response
            var capturedResponse: ResponseEnvelope?

            // Create result handler with send closure
            let handler = CodableResultHandler(
                callID: invocationEnvelope.callID,
                sendResponse: { response in
                    capturedResponse = response
                }
            )

            // Execute the distributed target on the local actor
            try await executeDistributedTarget(
                on: localActor,
                target: target,
                invocationDecoder: &decoder,
                handler: handler
            )

            // Get the captured response
            guard let responseEnvelope = capturedResponse else {
                throw RuntimeError.executionFailed(
                    "No response captured from local actor execution",
                    underlying: "Internal error"
                )
            }

            // Extract and verify void result
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
                throw error
            }
        }

        // Remote execution: require transport
        guard let transport = transport else {
            throw RuntimeError.transportFailed("No transport configured")
        }

        // Record target (it's passed as parameter, not yet in encoder)
        invocation.recordTarget(target)

        // Create InvocationEnvelope from encoder
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
            // Re-throw the remote error directly to preserve error type information
            throw error
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

