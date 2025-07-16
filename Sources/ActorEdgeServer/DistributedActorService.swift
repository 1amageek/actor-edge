import Foundation
import ActorEdgeCore
import Distributed
import GRPCCore
import GRPCProtobuf
import SwiftProtobuf
import Logging

/// gRPC service implementation for distributed actors
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
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
                return StreamingServerResponse(
                    accepted: .failure(RPCError(
                        code: .invalidArgument,
                        message: "No message received",
                        metadata: [:]
                    ))
                )
            }
            message = firstMessage
        } catch {
            return StreamingServerResponse(
                accepted: .failure(RPCError(
                    code: .unknown,
                    message: "Failed to read message: \(error)",
                    metadata: [:]
                ))
            )
        }
        
        logger.debug("Handling remote call", metadata: [
            "actorID": "\(message.actorID)",
            "method": "\(message.method)"
        ])
        
        do {
            // Parse actor ID
            let actorID = ActorEdgeID(message.actorID)
            
            // Find actor in the system
            guard let actor = await system.findActor(id: actorID) as? (any DistributedActor) else {
                logger.warning("Actor not found", metadata: ["actorID": "\(actorID)"])
                
                let errorEnvelope = Actoredge_ErrorEnvelope.with {
                    $0.typeURL = String(reflecting: ActorEdgeError.self)
                    $0.data = try! JSONEncoder().encode(ActorEdgeError.actorNotFound(actorID))
                    $0.description_p = "Actor not found: \(actorID)"
                }
                
                return StreamingServerResponse(
                    accepted: .failure(RPCError(
                        code: .notFound,
                        message: "Actor not found: \(actorID)",
                        metadata: [:]
                    ))
                )
            }
            
            // Create invocation decoder
            var decoder = ActorEdgeInvocationDecoder(
                system: system,
                payload: message.payload
            )
            
            // Create result handler
            let resultHandler = ActorEdgeResultHandler()
            
            // For now, we'll return empty data as we need to implement
            // the actual distributed method invocation
            // TODO: Implement proper distributed method invocation
            let resultData = Data()
            
            logger.debug("Remote call completed successfully", metadata: [
                "actorID": "\(actorID)",
                "method": "\(message.method)"
            ])
            
            return StreamingServerResponse(
                metadata: request.metadata
            ) { writer in
                try await writer.write(.with { $0.value = resultData })
                return [:]
            }
            
        } catch {
            logger.error("Remote call failed", metadata: [
                "actorID": "\(message.actorID)",
                "method": "\(message.method)",
                "error": "\(error)"
            ])
            
            // Serialize error to ErrorEnvelope
            let errorEnvelope = createErrorEnvelope(from: error)
            
            return StreamingServerResponse(
                accepted: .failure(RPCError(
                    code: .unknown,
                    message: error.localizedDescription,
                    metadata: [:]
                ))
            )
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
            return [:]
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

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension ActorEdgeSystem {
    /// Find an actor by ID in the system
    /// This is a server-side method that needs to be implemented
    func findActor(id: ActorEdgeID) async -> (any DistributedActor)? {
        // TODO: Implement actor registry
        return nil
    }
}