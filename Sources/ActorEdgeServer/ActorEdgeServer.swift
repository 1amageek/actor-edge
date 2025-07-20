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

import Foundation
import Distributed
import Logging
import ServiceLifecycle
import ActorEdgeCore

/// Protocol-independent server for distributed actors.
///
/// This server handles incoming invocation envelopes from any transport layer
/// and dispatches them to the appropriate actors using the distributed actor runtime.
public final class ActorEdgeServer: Sendable {
    private let system: ActorEdgeSystem
    private let transport: MessageTransport
    private let processor: DistributedInvocationProcessor
    private let logger: Logger
    
    /// Creates a new server with the given system and transport.
    public init(system: ActorEdgeSystem, transport: MessageTransport) {
        self.system = system
        self.transport = transport
        self.processor = DistributedInvocationProcessor(
            serialization: system.serialization
        )
        self.logger = Logger(label: "ActorEdge.Server")
    }
    
    /// Starts the server and begins processing messages.
    public func start() async throws {
        logger.info("Starting ActorEdgeServer")
        await processIncomingMessages()
    }
    
    /// Stops the server and releases resources.
    public func shutdown() async throws {
        logger.info("Shutting down ActorEdgeServer")
        
        // Close the transport
        try await transport.close()
        
        logger.info("ActorEdgeServer shutdown complete")
    }
    
    // MARK: - Private Methods
    
    /// Processes incoming messages from the transport.
    private func processIncomingMessages() async {
        logger.info("ActorEdgeServer started processing messages")
        
        for await envelope in transport.receive() {
            // Process each envelope concurrently
            Task {
                await self.handleIncomingEnvelope(envelope)
            }
        }
        
        logger.info("ActorEdgeServer stopped processing messages")
    }
    
    /// Handles a single incoming envelope.
    private func handleIncomingEnvelope(_ envelope: Envelope) async {
        logger.debug("Handling incoming envelope", metadata: [
            "messageID": "\(envelope.metadata.callID)",
            "type": "\(envelope.messageType)",
            "recipient": "\(envelope.recipient)"
        ])
        
        switch envelope.messageType {
        case .invocation:
            await handleInvocation(envelope)
        case .system:
            await handleSystemMessage(envelope)
        default:
            logger.warning("Unexpected message type on server", metadata: [
                "type": "\(envelope.messageType)"
            ])
        }
    }
    
    /// Handles method invocation messages.
    private func handleInvocation(_ envelope: Envelope) async {
        do {
            // Find the target actor
            guard let actor = system.findActor(id: envelope.recipient) else {
                logger.error("Actor not found", metadata: [
                    "actorID": "\(envelope.recipient)"
                ])
                try await sendErrorResponse(
                    to: envelope,
                    error: ActorEdgeError.actorNotFound(envelope.recipient)
                )
                return
            }
            
            // Extract target method
            let targetMethod = envelope.metadata.target
            guard !targetMethod.isEmpty else {
                logger.error("No target method specified")
                try await sendErrorResponse(
                    to: envelope,
                    error: ActorEdgeError.invocationError("No target method specified")
                )
                return
            }
            
            // Create decoder from envelope
            var decoder = try processor.createInvocationDecoder(from: envelope, system: system)
            
            // Create response writer
            let responseWriter = processor.createResponseWriter(
                for: envelope,
                transport: transport
            )
            
            // Create result handler
            let resultHandler = ActorEdgeResultHandler.forRemoteCall(
                system: system,
                callID: envelope.metadata.callID,
                responseWriter: responseWriter
            )
            
            // Execute the distributed target
            let target = RemoteCallTarget(targetMethod)
            
            logger.debug("Executing distributed target", metadata: [
                "actor": "\(type(of: actor))",
                "method": "\(targetMethod)"
            ])
            
            // The actual method invocation is handled by the Swift runtime
            try await system.executeDistributedTarget(
                on: actor,
                target: target,
                invocationDecoder: &decoder,
                handler: resultHandler
            )
            
        } catch {
            logger.error("Failed to handle invocation", metadata: [
                "error": "\(error)"
            ])
            do {
                try await sendErrorResponse(to: envelope, error: error)
            } catch {
                logger.error("Failed to send error response", metadata: [
                    "messageID": "\(envelope.metadata.callID)",
                    "error": "\(error)"
                ])
            }
        }
    }
    
    /// Handles system messages (e.g., health checks, actor lifecycle).
    private func handleSystemMessage(_ envelope: Envelope) async {
        // TODO: Implement system message handling
        logger.debug("Received system message", metadata: [
            "messageID": "\(envelope.metadata.callID)"
        ])
    }
    
    /// Sends an error response for a failed invocation.
    private func sendErrorResponse(to request: Envelope, error: Error) async throws {
        let errorEnvelope = try processor.createErrorEnvelope(
            to: request.sender ?? request.recipient,
            correlationID: request.metadata.callID,
            error: error,
            sender: request.recipient
        )
        
        _ = try await transport.send(errorEnvelope)
    }
}

// MARK: - Service Lifecycle Integration

extension ActorEdgeServer: Service {
    /// Runs the server as part of a ServiceLifecycle group.
    public func run() async throws {
        logger.info("ActorEdgeServer service started")
        
        // The server is already running via serverTask
        // Just wait for cancellation
        try await ContinuousClock().sleep(for: .seconds(Int64.max))
    }
}

// MARK: - Server Factory

public extension ActorEdgeServer {
    /// Creates a server with a gRPC transport.
    static func grpc(
        system: ActorEdgeSystem,
        host: String = "0.0.0.0",
        port: Int = 8000
    ) async throws -> ActorEdgeServer {
        // For server-side gRPC, we would need a different transport implementation
        // that accepts incoming connections rather than making outgoing ones
        // This is a placeholder for the actual implementation
        fatalError("Server-side gRPC transport not yet implemented")
    }
    
    /// Creates a server with an in-memory transport for testing.
    static func inMemory(
        system: ActorEdgeSystem,
        transport: InMemoryMessageTransport
    ) -> ActorEdgeServer {
        return ActorEdgeServer(system: system, transport: transport)
    }
}