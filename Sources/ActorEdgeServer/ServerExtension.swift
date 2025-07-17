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
        
        // Create service configuration
        let configuration = ActorEdgeService.Configuration(
            server: server,
            threads: System.coreCount,
            minGracePeriod: .seconds(5),
            avgLatencySeconds: 0.1
        )
        
        // Create and run the service with ServiceLifecycle
        let service = ActorEdgeService(configuration: configuration)
        let serviceGroup = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: logger
        )
        
        try await serviceGroup.run()
        
        logger.info("ActorEdge server shut down gracefully")
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