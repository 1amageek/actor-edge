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
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import ServiceContextModule
import Logging
import SwiftProtobuf
import NIOCore
import NIOPosix
import NIOSSL
import Metrics

/// gRPC server transport implementation of MessageTransport.
///
/// This transport implements a gRPC service that receives invocation requests
/// and sends back responses, bridging between gRPC and ActorEdge's envelope system.
public final class GRPCServerTransport: MessageTransport, RegistrableRPCService, Sendable {
    private let logger: Logger
    private let receiveStream: AsyncStream<Envelope>
    private let receiveContinuation: AsyncStream<Envelope>.Continuation
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    
    // Response correlation
    private let responseManager: ResponseStreamManager
    
    // Metrics
    private let requestCounter: Counter
    private let errorCounter: Counter
    
    /// Creates a new gRPC server transport.
    public init(eventLoopGroup: MultiThreadedEventLoopGroup, metricsNamespace: String = "actor_edge") {
        self.logger = Logger(label: "ActorEdge.Transport.gRPCServer")
        self.eventLoopGroup = eventLoopGroup
        self.responseManager = ResponseStreamManager()
        
        // Initialize metrics
        let metricNames = MetricNames(namespace: metricsNamespace)
        self.requestCounter = Counter(label: metricNames.messagesEnvelopesReceivedTotal)
        self.errorCounter = Counter(label: metricNames.messagesEnvelopesErrorsTotal)
        
        // Create receive stream
        (self.receiveStream, self.receiveContinuation) = AsyncStream<Envelope>.makeStream()
        
        logger.info("GRPCServerTransport initialized")
    }
    
    // MARK: - MessageTransport
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        // This is used by ActorEdgeServer to send responses back to clients
        logger.debug("Sending response", metadata: [
            "callID": "\(envelope.metadata.callID)",
            "type": "\(envelope.messageType)"
        ])
        
        // Deliver response to the appropriate writer
        await responseManager.deliverResponse(envelope)
        
        // Server-side send doesn't wait for a response
        return nil
    }
    
    public func receive() -> AsyncStream<Envelope> {
        receiveStream
    }
    
    public func close() async throws {
        logger.info("Closing GRPCServerTransport")
        receiveContinuation.finish()
        await responseManager.cancelAll()
    }
    
    public var isConnected: Bool {
        true // Server is always "connected"
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "grpc-server",
            attributes: [:],
            endpoint: nil,
            isSecure: false
        )
    }
    
    // MARK: - RegistrableRPCService
    
    public func registerMethods(with router: inout RPCRouter<some ServerTransport>) {
        let service = ServiceDescriptor(fullyQualifiedService: "ActorEdgeTransport")
        
        // Register unary RPC handler
        router.registerHandler(
            forMethod: MethodDescriptor(service: service, method: "Call"),
            deserializer: ProtobufDeserializer<ProtoEnvelope>(),
            serializer: ProtobufSerializer<ProtoEnvelope>(),
            handler: self.handleCall
        )
        
        // Register streaming RPC handler
        router.registerHandler(
            forMethod: MethodDescriptor(service: service, method: "Stream"),
            deserializer: ProtobufDeserializer<ProtoEnvelope>(),
            serializer: ProtobufSerializer<ProtoEnvelope>(),
            handler: self.handleStream
        )
        
        logger.info("Registered gRPC methods")
    }
    
    // MARK: - RPC Handlers
    
    private func handleCall(
        request: StreamingServerRequest<ProtoEnvelope>,
        context: ServerContext
    ) async throws -> StreamingServerResponse<ProtoEnvelope> {
        return StreamingServerResponse { [weak self] writer in
            guard let self = self else { return [:] }
            self.requestCounter.increment()
            
            // Process incoming messages
            for try await protoEnvelope in request.messages {
                do {
                    let envelope = try Envelope(from: protoEnvelope)
                    
                    self.logger.debug("Received call", metadata: [
                        "callID": "\(envelope.metadata.callID)",
                        "recipient": "\(envelope.recipient)",
                        "type": "\(envelope.messageType)"
                    ])
                    
                    // Create a response stream for this call
                    let responseStream = await self.responseManager.createStream(
                        for: envelope.metadata.callID,
                        writer: writer
                    )
                    
                    // Deliver envelope to the receive stream for processing
                    self.receiveContinuation.yield(envelope)
                    
                    // Wait for the response from ActorEdgeServer
                    let responseEnvelope = await responseStream.first { _ in true }
                    
                    if responseEnvelope == nil {
                        // If no response received, send an error
                        let errorEnvelope = Envelope.error(
                            to: envelope.sender ?? envelope.recipient,
                            from: envelope.recipient,
                            callID: envelope.metadata.callID,
                            manifest: SerializationManifest.json(),
                            payload: try JSONEncoder().encode(["error": "No response received"])
                        )
                        let protoError = errorEnvelope.toProto()
                        try await writer.write(protoError)
                    }
                    // Response is written by ResponseStreamManager
                    
                } catch {
                    self.errorCounter.increment()
                    self.logger.error("Failed to handle message", metadata: [
                        "error": "\(error)"
                    ])
                    // Error handling is done in the do block where envelope is available
                    throw error
                }
            }
            
            // Return empty metadata
            return [:]
        }
    }
    
    private func handleStream(
        request: StreamingServerRequest<ProtoEnvelope>,
        context: ServerContext
    ) async throws -> StreamingServerResponse<ProtoEnvelope> {
        // Streaming implementation would go here
        // For now, just acknowledge the stream
        logger.info("Stream handler called (not implemented)")
        throw RPCError(code: .unimplemented, message: "Streaming not yet implemented")
    }
}

/// Manages response correlation for gRPC server transport.
/// Maps call IDs to response writers and handles asynchronous response delivery.
private actor ResponseStreamManager {
    private var pendingCalls: [String: ResponseWriter] = [:]
    
    struct ResponseWriter {
        let writer: RPCWriter<ProtoEnvelope>
        let continuation: AsyncStream<Envelope>.Continuation
    }
    
    /// Creates a response stream for a call ID.
    func createStream(
        for callID: String,
        writer: RPCWriter<ProtoEnvelope>
    ) -> AsyncStream<Envelope> {
        let (stream, continuation) = AsyncStream<Envelope>.makeStream()
        
        Task {
            await self.registerWriter(
                callID: callID,
                writer: writer,
                continuation: continuation
            )
        }
        
        return stream
    }
    
    /// Registers a writer for a call ID.
    private func registerWriter(
        callID: String,
        writer: RPCWriter<ProtoEnvelope>,
        continuation: AsyncStream<Envelope>.Continuation
    ) {
        pendingCalls[callID] = ResponseWriter(
            writer: writer,
            continuation: continuation
        )
    }
    
    /// Delivers a response envelope to the appropriate writer.
    func deliverResponse(_ envelope: Envelope) async {
        let callID = envelope.metadata.callID
        
        guard let responseWriter = pendingCalls[callID] else {
            // No writer found for this call ID
            return
        }
        
        // Convert envelope to proto and write
        let protoEnvelope = envelope.toProto()
        do {
            try await responseWriter.writer.write(protoEnvelope)
            
            // Notify the stream
            responseWriter.continuation.yield(envelope)
            responseWriter.continuation.finish()
            
            // Clean up
            pendingCalls.removeValue(forKey: callID)
        } catch {
            // Error writing response, clean up
            responseWriter.continuation.finish()
            pendingCalls.removeValue(forKey: callID)
        }
    }
    
    /// Cancels all pending calls.
    func cancelAll() {
        for (_, writer) in pendingCalls {
            writer.continuation.finish()
        }
        pendingCalls.removeAll()
    }
}