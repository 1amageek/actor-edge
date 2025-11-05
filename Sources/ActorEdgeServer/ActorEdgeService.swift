import Foundation
import ServiceLifecycle
import ActorEdgeCore
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOPosix
import Logging
import Metrics
import Distributed

/// ServiceLifecycle-compatible service for ActorEdge
public actor ActorEdgeService: Service {
    
    /// Configuration for the service
    public struct Configuration: Sendable {
        public let server: any Server
        public let threads: Int
        public let minGracePeriod: TimeAmount
        public let avgLatencySeconds: Double
        
        public init(
            server: any Server,
            threads: Int = System.coreCount,
            minGracePeriod: TimeAmount = .seconds(5),
            avgLatencySeconds: Double = 0.1
        ) {
            self.server = server
            self.threads = threads
            self.minGracePeriod = minGracePeriod
            self.avgLatencySeconds = avgLatencySeconds
        }
    }
    
    // Dependencies
    private let configuration: Configuration
    private let logger: Logger
    
    // Managed resources
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var grpcServer: GRPCServer<HTTP2ServerTransport.Posix>?
    private var actorSystem: ActorEdgeSystem?
    
    public init(configuration: Configuration) {
        self.configuration = configuration
        self.logger = Logger(label: "ActorEdge.Service")
    }
    
    // MARK: - Service Lifecycle
    
    public func run() async throws {
        logger.info("Starting ActorEdge service...")
        
        // Bootstrap metrics if configured
        configuration.server.metrics.bootstrap()
        
        // Create event loop group
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: configuration.threads)
        eventLoopGroup = elg
        
        // Create actor system (server-side doesn't need transport for local actors)
        let systemConfig = ActorEdgeSystem.Configuration(
            metrics: configuration.server.metrics,
            timeout: configuration.server.timeout,
            maxRetries: configuration.server.maxRetries
        )
        let system = ActorEdgeSystem(configuration: systemConfig)
        actorSystem = system
        
        // Set pre-assigned IDs before creating actors
        system.setPreAssignedIDs(configuration.server.actorIDs)
        
        // Create actors - they will use the pre-assigned IDs
        let actors = configuration.server.actors(actorSystem: system)
        
        // Log the actors that were created
        for actor in actors {
            logger.info("Created actor", metadata: ["type": "\(type(of: actor))"])
        }
        
        // Create HTTP/2 transport for gRPC
        let host = configuration.server.host
        let port = configuration.server.port

        let transportConfig: HTTP2ServerTransport.Posix
        if let tlsConfig = configuration.server.tls {
            // Configure TLS using grpc-swift's TLS API
            do {
                let grpcTLS = try tlsConfig.toGRPCTransportSecurity()
                transportConfig = HTTP2ServerTransport.Posix(
                    address: .ipv4(host: host, port: port),
                    transportSecurity: grpcTLS
                )
                logger.info("TLS configured successfully")
            } catch {
                logger.error("Failed to configure TLS", metadata: ["error": "\(error)"])
                throw error
            }
        } else {
            transportConfig = HTTP2ServerTransport.Posix(
                address: .ipv4(host: host, port: port),
                transportSecurity: .plaintext
            )
        }
        
        // Create distributed actor service
        let distributedActorService = DistributedActorService(system: system)

        // Create gRPC server
        let grpc = GRPCServer(transport: transportConfig, services: [distributedActorService])
        grpcServer = grpc
        
        logger.info("ActorEdge service configured", metadata: [
            "host": "\(host)",
            "port": "\(port)",
            "tls": "\(configuration.server.tls != nil)",
            "maxConnections": "\(configuration.server.maxConnections)"
        ])
        
        // Start the gRPC server
        do {
            try await grpc.serve()
        } catch {
            self.logger.error("gRPC server error", metadata: ["error": "\(error)"])
            throw error
        }
    }
    
    // MARK: - Graceful Shutdown
    
    public func shutdown() async throws {
        logger.info("Starting graceful shutdown...")
        
        // Stop the gRPC server
        // Note: GRPCServer in grpc-swift 2.0 doesn't have explicit stop method
        // It will be stopped when the task is cancelled
        logger.info("Cancelling gRPC server task")
        
        // Shutdown event loop group
        if let elg = eventLoopGroup {
            try? await elg.shutdownGracefully()
            logger.info("Event loop group shut down")
        }
        
        logger.info("Graceful shutdown completed")
    }
    
}

