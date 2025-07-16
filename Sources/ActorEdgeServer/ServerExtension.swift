import Foundation
import ActorEdgeCore
import ServiceLifecycle
import NIOCore
// import GRPCServiceLifecycle
import GRPCCore
import GRPCNIOTransportHTTP2
import Logging
import Distributed
import NIO
import NIOSSL

// MARK: - Server Extension

public extension Server {
    /// Main entry point for ActorEdge servers
    static func main() async throws {
        // Initialize logging
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        let logger = Logger(label: "ActorEdge.Server")
        
        logger.info("Starting ActorEdge server...")
        
        // Create server instance
        let server = Self()
        
        // Create actor system
        let system = ActorEdgeSystem()
        
        // Get server's actors with the system
        let actors = server.actors(actorSystem: system)
        
        // Register server's actors with the system
        for (index, actor) in actors.enumerated() {
            let actorID = ActorEdgeID("actor-\(index)")
            await system.registerActor(actor, id: actorID)
            logger.info("Registered actor", metadata: ["id": "\(actorID)", "type": "\(type(of: actor))"])
        }
        
        // Configure transport security
        let transportSecurity: HTTP2ServerTransport.Posix.TransportSecurity
        if let tlsConfig = server.tls {
            // Note: grpc-swift 2.0 has limited TLS configuration API
            // The full TLS configuration is not exposed in the public API yet
            // For basic TLS, we can use the available options
            
            if tlsConfig.certificateChainSources.isEmpty {
                logger.warning("TLS configuration provided but no certificates found. Using plaintext.")
                transportSecurity = .plaintext
            } else {
                // Log warning about limited TLS support
                logger.warning("TLS configuration provided. Note: Full TLS configuration support is limited in grpc-swift 2.0.")
                
                // For now, we use plaintext until grpc-swift exposes the full TLS API
                // In production, you would need to use the available TLS methods when they become public
                transportSecurity = .plaintext
                
                // TODO: When grpc-swift 2.0 exposes the TLS configuration API, use:
                // transportSecurity = .tls(
                //     certificateChain: tlsConfig.certificateChain.map { .certificate($0) },
                //     privateKey: .privateKey(tlsConfig.privateKey)
                // )
            }
        } else {
            transportSecurity = .plaintext
        }
        
        // Create gRPC server
        let grpcServer = GRPCServer(
            transport: HTTP2ServerTransport.Posix(
                address: .ipv4(host: server.host, port: server.port),
                transportSecurity: transportSecurity,
                config: .defaults { config in
                    // Configure server settings
                    config.http2.targetWindowSize = 65536
                    config.http2.maxFrameSize = 16384
                }
            ),
            services: [DistributedActorService(system: system)],
            interceptors: server.middleware.compactMap { $0.asGRPCInterceptor() }
        )
        
        logger.info("ActorEdge server configured", metadata: [
            "host": "\(server.host)",
            "port": "\(server.port)",
            "tls": "\(server.tls != nil)",
            "maxConnections": "\(server.maxConnections)"
        ])
        
        logger.info("Starting gRPC server...")
        
        // Run the gRPC server directly
        // TODO: Integrate with ServiceLifecycle properly
        try await grpcServer.serve()
        
        logger.info("ActorEdge server shut down gracefully")
    }
}

// MARK: - ActorEdgeSystem Extensions for Server

extension ActorEdgeSystem {
    /// Register any distributed actor with the system
    func registerActor(_ actor: any DistributedActor, id: ActorEdgeID) async {
        guard let registry = registry else {
            return
        }
        await registry.register(actor, id: id)
    }
}

// MARK: - ServerMiddleware to gRPC Interceptor Conversion

extension ServerMiddleware {
    /// Convert ServerMiddleware to gRPC interceptor if possible
    func asGRPCInterceptor() -> (any ServerInterceptor)? {
        // TODO: Implement middleware to interceptor conversion
        // For now, return nil as we haven't implemented interceptor support yet
        return nil
    }
}