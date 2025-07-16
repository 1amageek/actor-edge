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

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public extension Server {
    /// Main entry point for ActorEdge servers
    static func main() async throws {
        // Initialize logging
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        let logger = Logger(label: "ActorEdge.Server")
        
        logger.info("Starting ActorEdge server...")
        
        // Create actor system
        let system = ActorEdgeSystem()
        
        // Create server instance
        let server = Self()
        
        // Configure transport security
        let transportSecurity: HTTP2ServerTransport.Posix.TransportSecurity
        if let tlsConfig = server.tls {
            // For now, use default TLS config
            // In production, should use tlsConfig.certificateChain and privateKey
            // Use self-signed certificate for testing
            // In production, load from tlsConfig
            transportSecurity = .plaintext // TODO: Implement proper TLS support
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

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension ActorEdgeSystem {
    /// Register a server instance with the system
    func registerServer<S: Server>(_ server: S) async {
        // TODO: Implement server registry for distributed actors
        // For now, this is a placeholder
    }
}

// MARK: - ServerMiddleware to gRPC Interceptor Conversion

@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
extension ServerMiddleware {
    /// Convert ServerMiddleware to gRPC interceptor if possible
    func asGRPCInterceptor() -> (any ServerInterceptor)? {
        // TODO: Implement middleware to interceptor conversion
        // For now, return nil as we haven't implemented interceptor support yet
        return nil
    }
}