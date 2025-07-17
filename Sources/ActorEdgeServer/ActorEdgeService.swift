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
    private var callLifecycleManager: CallLifecycleManager?
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
        
        // Create call lifecycle manager
        let clm = CallLifecycleManager(
            eventLoopGroup: elg,
            metricsNamespace: configuration.server.metrics.namespace
        )
        callLifecycleManager = clm
        
        // Create actor system
        let system = ActorEdgeSystem(metricsNamespace: configuration.server.metrics.namespace)
        actorSystem = system
        
        // Register actors
        let actors = configuration.server.actors(actorSystem: system)
        let providedIDs = configuration.server.actorIDs
        
        for (index, actor) in actors.enumerated() {
            let actorID: ActorEdgeID
            if index < providedIDs.count {
                actorID = ActorEdgeID(providedIDs[index])
            } else {
                actorID = ActorEdgeID("actor-\(index)")
            }
            
            await system.registerActor(actor, id: actorID)
            logger.info("Registered actor", metadata: ["id": "\(actorID)", "type": "\(type(of: actor))"])
        }
        
        // Configure transport security
        let transportSecurity = configureTransportSecurity()
        
        // Create gRPC server
        let server = GRPCServer(
            transport: HTTP2ServerTransport.Posix(
                address: .ipv4(host: configuration.server.host, port: configuration.server.port),
                transportSecurity: transportSecurity,
                config: .defaults { config in
                    config.http2.targetWindowSize = 65536
                    config.http2.maxFrameSize = 16384
                }
            ),
            services: [DistributedActorService(system: system)],
            interceptors: configuration.server.middleware.compactMap { $0.asGRPCInterceptor() }
        )
        grpcServer = server
        
        logger.info("ActorEdge service configured", metadata: [
            "host": "\(configuration.server.host)",
            "port": "\(configuration.server.port)",
            "tls": "\(configuration.server.tls != nil)",
            "maxConnections": "\(configuration.server.maxConnections)"
        ])
        
        // Monitor lifecycle manager state
        Task {
            guard let clm = self.callLifecycleManager else { return }
            for await state in clm.states {
                logger.info("CallLifecycleManager state changed", metadata: ["state": "\(state)"])
            }
        }
        
        // Run the gRPC server
        try await server.serve()
    }
    
    // MARK: - Graceful Shutdown
    
    public func shutdown() async throws {
        logger.info("Starting graceful shutdown...")
        
        // Calculate dynamic grace period based on in-flight calls
        let gracePeriod = calculateGracePeriod()
        logger.info("Grace period calculated", metadata: [
            "seconds": "\(gracePeriod.nanoseconds / 1_000_000_000)"
        ])
        
        // Drain in-flight calls
        if let clm = callLifecycleManager {
            let deadline = NIODeadline.now() + gracePeriod
            await clm.drain(until: deadline)
        }
        
        // Note: GRPCServer will be stopped when the run() method completes
        logger.info("gRPC server will stop when run() completes")
        
        // Shutdown event loop group
        if let elg = eventLoopGroup {
            try? await elg.shutdownGracefully()
            logger.info("Event loop group shut down")
        }
        
        logger.info("Graceful shutdown completed")
    }
    
    // MARK: - Private Helpers
    
    private func configureTransportSecurity() -> HTTP2ServerTransport.Posix.TransportSecurity {
        if let tlsConfig = configuration.server.tls {
            if tlsConfig.certificateChainSources.isEmpty {
                logger.warning("TLS configuration provided but no certificates found. Using plaintext.")
                return .plaintext
            } else {
                // TODO: Full TLS support when grpc-swift 2.0 exposes the API
                logger.warning("TLS configuration provided. Note: Full TLS support is limited in grpc-swift 2.0.")
                return .plaintext
            }
        }
        return .plaintext
    }
    
    private func calculateGracePeriod() -> TimeAmount {
        guard let clm = callLifecycleManager else {
            return configuration.minGracePeriod
        }
        
        let inFlightCount = clm.inFlightCount
        let calculatedGrace = TimeAmount.seconds(
            Int64(Double(inFlightCount) * configuration.avgLatencySeconds)
        )
        
        // Return the maximum of minimum grace period and calculated grace
        return max(configuration.minGracePeriod, calculatedGrace)
    }
}

// MARK: - ActorEdgeSystem Server Extensions

extension ActorEdgeSystem {
    /// Register any distributed actor with the system
    func registerActor(_ actor: any DistributedActor, id: ActorEdgeID) async {
        guard let registry = registry else {
            return
        }
        await registry.register(actor, id: id)
    }
}