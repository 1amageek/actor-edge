import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import ServiceContextModule
import Logging
import SwiftProtobuf

/// gRPC-based transport implementation for ActorEdge
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public final class GRPCActorTransport: ActorTransport, Sendable {
    private let transport: HTTP2ClientTransport.Posix
    private let logger: Logger
    private let endpoint: String
    
    public init(_ endpoint: String, tls: ClientTLSConfiguration? = nil) async throws {
        self.endpoint = endpoint
        self.logger = Logger(label: "ActorEdge.Transport")
        
        // Parse endpoint to extract host and port
        let components = endpoint.split(separator: ":")
        let host = String(components[0])
        let port = components.count > 1 ? Int(components[1]) ?? 443 : 443
        
        // Create HTTP2 transport with appropriate security
        if tls != nil {
            self.transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .tls
            )
        } else {
            self.transport = try HTTP2ClientTransport.Posix(
                target: .dns(host: host, port: port),
                transportSecurity: .plaintext
            )
        }
        
        logger.info("GRPCActorTransport initialized", metadata: [
            "endpoint": "\(endpoint)",
            "tls": "\(tls != nil)"
        ])
    }
    
    public func remoteCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> Data {
        // Create protobuf request
        let request = Actoredge_RemoteCallRequest.with {
            $0.actorID = actorID.description
            $0.method = method
            $0.payload = arguments
            
            // Add trace context to metadata if available
            if let traceID = context.traceID {
                $0.metadata["trace-id"] = traceID
            }
        }
        
        // Use withGRPCClient to make the call
        let response = try await withGRPCClient(transport: transport) { client in
            // Create metadata from context
            var metadata = Metadata()
            if let traceID = context.traceID {
                metadata.addString(traceID, forKey: "trace-id")
            }
            
            // Make unary RPC call
            let descriptor = MethodDescriptor(
                service: ServiceDescriptor(fullyQualifiedService: "actoredge.DistributedActor"),
                method: "RemoteCall"
            )
            
            return try await client.unary(
                request: ClientRequest(message: request, metadata: metadata),
                descriptor: descriptor,
                serializer: ProtobufSerializer<Actoredge_RemoteCallRequest>(),
                deserializer: ProtobufDeserializer<Actoredge_RemoteCallResponse>(),
                options: .defaults
            ) { response in
                // Return the response directly
                response
            }
        }
        
        // Handle response
        let message = try response.message
        switch message.result {
        case .value(let data):
            return data
        case .error(let errorEnvelope):
            throw deserializeError(errorEnvelope)
        case .none:
            throw ActorEdgeError.invalidResponse
        }
    }
    
    public func remoteCallVoid(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws {
        // Reuse remoteCall but ignore the return value
        _ = try await remoteCall(
            on: actorID,
            method: method,
            arguments: arguments,
            context: context
        )
    }
    
    public func streamCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> AsyncThrowingStream<Data, Error> {
        // TODO: Implement bidirectional streaming
        throw ActorEdgeError.transportError("Streaming not yet implemented")
    }
    
    // Helper to deserialize error from ErrorEnvelope
    private func deserializeError(_ envelope: Actoredge_ErrorEnvelope) -> Error {
        let errorEnvelope = ErrorEnvelope(
            typeURL: envelope.typeURL,
            data: envelope.data
        )
        return ActorEdgeError.remoteError(errorEnvelope)
    }
}

// MARK: - ServiceContext Extensions

private extension ServiceContext {
    var traceID: String? {
        // TODO: Extract trace ID from context
        return nil
    }
}

// MARK: - ClientTLSConfiguration

public struct ClientTLSConfiguration: Sendable {
    public init() {}
}