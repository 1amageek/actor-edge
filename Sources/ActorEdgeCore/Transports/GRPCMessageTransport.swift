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

/// gRPC implementation of MessageTransport.
///
/// This transport converts Envelope messages to gRPC protobuf messages
/// and vice versa, providing protocol independence for the actor system.
public final class GRPCMessageTransport: MessageTransport, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let logger: Logger
    private let endpoint: String
    private let eventLoopGroup: MultiThreadedEventLoopGroup
    private let clientTask: Task<Void, Error>
    
    // Metrics
    private let requestCounter: Counter
    private let errorCounter: Counter
    private let metricNames: TransportMetricNames
    
    /// Creates a new gRPC message transport.
    public init(endpoint: String, tls: ClientTLSConfiguration? = nil, configuration: ActorEdgeSystem.Configuration = .default) async throws {
        self.endpoint = endpoint
        self.logger = Logger(label: "ActorEdge.Transport.gRPC")
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        // Initialize metrics
        self.metricNames = TransportMetricNames(namespace: configuration.metrics.namespace)
        self.requestCounter = Counter(label: metricNames.messagesEnvelopesSentTotal)
        self.errorCounter = Counter(label: metricNames.messagesEnvelopesErrorsTotal)
        
        // Parse endpoint
        let components = endpoint.split(separator: ":")
        let host = String(components[0])
        let port = components.count > 1 ? Int(components[1]) ?? 443 : 443
        
        // Create HTTP2 transport
        let transport: HTTP2ClientTransport.Posix
        if tls != nil {
            // TODO: Implement proper TLS when grpc-swift 2.0 exposes the configuration API
            logger.warning("TLS configuration provided but not fully implemented. Using plaintext for now.")
            transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
        } else {
            transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
        }
        
        // Create gRPC client
        self.client = GRPCClient(transport: transport)
        
        // Run client connections
        let clientRef = self.client
        self.clientTask = Task {
            try await clientRef.runConnections()
        }
        
        logger.info("GRPCMessageTransport initialized", metadata: [
            "endpoint": "\(endpoint)",
            "tls": "\(tls != nil)"
        ])
    }
    
    // MARK: - MessageTransport
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        logger.debug("Sending envelope", metadata: [
            "callID": "\(envelope.metadata.callID)",
            "recipient": "\(envelope.recipient)",
            "type": "\(envelope.messageType)"
        ])
        
        requestCounter.increment()
        
        // Convert envelope to protobuf
        let protoEnvelope = envelope.toProto()
        
        // Create metadata
        var metadata = Metadata()
        for (key, value) in envelope.metadata.headers {
            metadata.addString(value, forKey: key)
        }
        
        // Make unary RPC call
        let descriptor = MethodDescriptor(
            service: ServiceDescriptor(fullyQualifiedService: "ActorEdgeTransport"),
            method: "Call"
        )
        
        do {
            let response = try await client.unary(
                request: ClientRequest(message: protoEnvelope, metadata: metadata),
                descriptor: descriptor,
                serializer: ProtobufSerializer<ProtoEnvelope>(),
                deserializer: ProtobufDeserializer<ProtoEnvelope>(),
                options: .defaults
            ) { response in
                response
            }
            
            let protoResponse = try response.message
            
            // Convert protobuf response to envelope
            let responseEnvelope = try Envelope(from: protoResponse)
            
            logger.debug("Received response envelope", metadata: [
                "callID": "\(responseEnvelope.metadata.callID)",
                "type": "\(responseEnvelope.messageType)"
            ])
            
            return responseEnvelope
            
        } catch {
            errorCounter.increment()
            logger.error("gRPC call failed", metadata: [
                "error": "\(error)"
            ])
            throw TransportError.sendFailed(reason: error.localizedDescription)
        }
    }
    
    public func receive() -> AsyncStream<Envelope> {
        // For client transports, we typically don't receive unsolicited messages
        // This would be implemented for server-side transport
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    public func close() async throws {
        logger.info("Closing GRPCMessageTransport")
        
        // Cancel the client task
        clientTask.cancel()
        
        // Shutdown event loop group
        try await eventLoopGroup.shutdownGracefully()
    }
    
    public var isConnected: Bool {
        // TODO: Implement proper connection status tracking
        return !clientTask.isCancelled
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "grpc",
            attributes: [
                "endpoint": endpoint,
                "http2": "true"
            ],
            endpoint: endpoint,
            isSecure: false // TODO: Update when TLS is implemented
        )
    }
}

/// Manages response streams for bidirectional communication.
private actor ResponseStreamManager {
    private var continuations: [String: AsyncStream<Envelope>.Continuation] = [:]
    
    func createStream(for callID: String) -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            self.setContinuation(continuation, for: callID)
        }
    }
    
    private func setContinuation(_ continuation: AsyncStream<Envelope>.Continuation, for callID: String) {
        continuations[callID] = continuation
    }
    
    func deliverResponse(_ envelope: Envelope) {
        guard let continuation = continuations[envelope.metadata.callID] else {
            return
        }
        continuation.yield(envelope)
        continuation.finish()
        continuations.removeValue(forKey: envelope.metadata.callID)
    }
    
    func cancelStream(for callID: String) {
        continuations[callID]?.finish()
        continuations.removeValue(forKey: callID)
    }
    
    func cancelAll() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

/// Metric names for transport operations.
struct TransportMetricNames {
    let namespace: String
    
    var messagesEnvelopesSentTotal: String {
        "\(namespace).messages.envelopes.sent.total"
    }
    
    var messagesEnvelopesErrorsTotal: String {
        "\(namespace).messages.envelopes.errors.total"
    }
}

