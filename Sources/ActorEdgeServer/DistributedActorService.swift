import Foundation
import ActorEdgeCore
import Distributed
import GRPCCore
import GRPCProtobuf
import SwiftProtobuf
import Logging

/// gRPC service implementation for distributed actors
public final class DistributedActorService: RegistrableRPCService {
    private let system: ActorEdgeSystem
    private let logger: Logger
    
    public init(system: ActorEdgeSystem) {
        self.system = system
        self.logger = Logger(label: "ActorEdge.Service")
    }
    
    public func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        // Register RemoteCall handler
        router.registerHandler(
            forMethod: MethodDescriptor(
                service: ServiceDescriptor(fullyQualifiedService: "actoredge.DistributedActor"),
                method: "RemoteCall"
            ),
            deserializer: ProtobufDeserializer<Actoredge_RemoteCallRequest>(),
            serializer: ProtobufSerializer<Actoredge_RemoteCallResponse>()
        ) { (request: StreamingServerRequest<Actoredge_RemoteCallRequest>, context: ServerContext) in
            await self.handleRemoteCall(request: request, context: context)
        }
        
        // Register StreamCall handler for bidirectional streaming
        router.registerHandler(
            forMethod: MethodDescriptor(
                service: ServiceDescriptor(fullyQualifiedService: "actoredge.DistributedActor"),
                method: "StreamCall"
            ),
            deserializer: ProtobufDeserializer<Actoredge_RemoteStreamPacket>(),
            serializer: ProtobufSerializer<Actoredge_RemoteStreamPacket>()
        ) { (request: StreamingServerRequest<Actoredge_RemoteStreamPacket>, context: ServerContext) in
            await self.handleStreamCall(request: request, context: context)
        }
    }
    
    private func handleRemoteCall(
        request: StreamingServerRequest<Actoredge_RemoteCallRequest>,
        context: ServerContext
    ) async -> StreamingServerResponse<Actoredge_RemoteCallResponse> {
        // Get the first message from the stream
        let message: Actoredge_RemoteCallRequest
        do {
            guard let firstMessage = try await request.messages.first(where: { _ in true }) else {
                // Return error response with empty call_id since we don't have a message
                return StreamingServerResponse(
                    metadata: request.metadata
                ) { writer in
                    try await writer.write(.with {
                        $0.callID = ""  // No call_id available
                        $0.error = self.createErrorEnvelope(
                            from: ActorEdgeError.transportError("No message received")
                        )
                    })
                    return request.metadata
                }
            }
            message = firstMessage
        } catch {
            // Return error response with empty call_id since we couldn't read the message
            return StreamingServerResponse(
                metadata: request.metadata
            ) { writer in
                try await writer.write(.with {
                    $0.callID = ""  // No call_id available
                    $0.error = self.createErrorEnvelope(
                        from: ActorEdgeError.transportError("Failed to read message: \(error)")
                    )
                })
                return request.metadata
            }
        }
        
        logger.debug("Handling remote call", metadata: [
            "actorID": "\(message.actorID)",
            "method": "\(message.method)"
        ])
        
        // Process the request and write response directly in the streaming response closure
        return StreamingServerResponse(
            metadata: request.metadata
        ) { [self] writer in
            do {
                // Parse actor ID
                let actorID = ActorEdgeID(message.actorID)
                
                // Find actor in the system
                guard let actor = await system.findActor(id: actorID) else {
                    logger.warning("Actor not found", metadata: ["actorID": "\(actorID)"])
                    
                    try await writer.write(.with {
                        $0.callID = message.callID
                        $0.error = self.createErrorEnvelope(
                            from: ActorEdgeError.actorNotFound(actorID)
                        )
                    })
                    return request.metadata
                }
                
                // Create invocation decoder
                var decoder = try ActorEdgeInvocationDecoder(
                    system: system,
                    payload: message.payload
                )
                
                // Create response writer that writes directly to the gRPC stream
                let responseWriter = GRPCResponseWriter(
                    callID: message.callID,
                    writeResponse: writer.write
                )
                
                // Create result handler with response writer
                let resultHandler = ActorEdgeResultHandler.forRemoteCall(
                    system: system,
                    callID: message.callID,
                    responseWriter: responseWriter
                )
                
                // Create RemoteCallTarget from method name
                let target = RemoteCallTarget(message.method)
                
                // Execute the distributed method using the actor system
                // This should complete synchronously after calling the result handler
                try await system.executeDistributedTarget(
                    on: actor,
                    target: target,
                    invocationDecoder: &decoder,
                    handler: resultHandler
                )
                
                logger.debug("Remote call completed successfully", metadata: [
                    "actorID": "\(actorID)",
                    "method": "\(message.method)"
                ])
                
            } catch {
                logger.error("Remote call failed", metadata: [
                    "actorID": "\(message.actorID)",
                    "method": "\(message.method)",
                    "error": "\(error)"
                ])
                
                try await writer.write(.with {
                    $0.callID = message.callID
                    $0.error = self.createErrorEnvelope(from: error)
                })
            }
            
            return request.metadata
        }
    }
    
    private func handleStreamCall(
        request: StreamingServerRequest<Actoredge_RemoteStreamPacket>,
        context: ServerContext
    ) async -> StreamingServerResponse<Actoredge_RemoteStreamPacket> {
        // TODO: Implement streaming support
        return StreamingServerResponse(metadata: request.metadata) { writer in
            try await writer.write(.with {
                $0.streamID = "not-implemented"
                $0.error = self.createErrorEnvelope(
                    from: ActorEdgeError.transportError("Streaming not yet implemented")
                )
            })
            return request.metadata
        }
    }
    
    private func createErrorEnvelope(from error: Error) -> Actoredge_ErrorEnvelope {
        do {
            if let actorEdgeError = error as? ActorEdgeError {
                return Actoredge_ErrorEnvelope.with {
                    $0.typeURL = String(reflecting: ActorEdgeError.self)
                    $0.data = try! JSONEncoder().encode(actorEdgeError)
                    $0.description_p = String(describing: actorEdgeError)
                }
            } else {
                // Wrap unknown errors
                let errorData = try JSONEncoder().encode([
                    "type": String(reflecting: type(of: error)),
                    "description": error.localizedDescription
                ])
                
                return Actoredge_ErrorEnvelope.with {
                    $0.typeURL = String(reflecting: type(of: error))
                    $0.data = errorData
                    $0.description_p = error.localizedDescription
                }
            }
        } catch {
            // Fallback for encoding errors
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "EncodingError"
                $0.data = Data()
                $0.description_p = "Failed to encode error: \(error)"
            }
        }
    }
}

// MARK: - ActorEdgeSystem Extensions

extension ActorEdgeSystem {
    /// Find an actor by ID in the system
    func findActor(id: ActorEdgeID) async -> (any DistributedActor)? {
        guard isServer, let registry = registry else {
            return nil
        }
        return await registry.find(id: id)
    }
}