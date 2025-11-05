import Foundation
import Testing
import Distributed
@testable import ActorEdgeCore
@testable import ActorEdgeServer
import ServiceLifecycle
import Logging
import GRPCCore
import GRPCNIOTransportHTTP2

/// Utility for managing Server lifecycle in tests
/// Uses the actual Server protocol - no transport-specific code
public actor ServerLifecycleManager {
    private var serviceGroup: ServiceGroup?
    private var actorIDs: [ActorEdgeID] = []
    private var service: ActorEdgeService?

    /// Start a server (any Server implementation)
    /// Returns the actor IDs from the server
    public func start<S: Server>(_ server: S) async throws -> [ActorEdgeID] {
        guard serviceGroup == nil else {
            throw TestServerError.serverAlreadyRunning
        }

        var logger = Logger(label: "test-server")
        logger.logLevel = .critical  // Suppress logs during tests

        // Create service configuration using the Server protocol
        let configuration = ActorEdgeService.Configuration(
            server: server,
            threads: 1,
            minGracePeriod: .seconds(1),
            avgLatencySeconds: 0.1
        )

        let service = ActorEdgeService(configuration: configuration)
        self.service = service

        let group = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [],  // Don't listen for signals in tests
            logger: logger
        )

        self.serviceGroup = group

        // Start in background
        Task {
            do {
                try await group.run()
            } catch {
                // Server stopped (expected during shutdown)
            }
        }

        // Wait for server to be ready by checking listeningAddress
        var attempts = 0
        let maxAttempts = 50 // 5 seconds max (50 * 100ms)

        while attempts < maxAttempts {
            if await service.listeningAddress != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }

        // Store and return actor IDs from server
        self.actorIDs = server.actorIDs
        return server.actorIDs
    }

    /// Stop the server
    public func stop() async throws {
        guard let group = serviceGroup else {
            return
        }

        await group.triggerGracefulShutdown()
        try await Task.sleep(for: .milliseconds(500))
        serviceGroup = nil
    }
}

/// Utility for managing gRPC client lifecycle in tests
public actor ClientLifecycleManager {
    private var runConnectionsTask: Task<Void, Error>?
    private var grpcClient: GRPCClient<HTTP2ClientTransport.Posix>?

    /// Create and start a gRPC client with background connection management
    public func createClient(endpoint: String, tls: ClientTLSConfiguration? = nil, configuration: ActorEdgeSystem.Configuration = .default) async throws -> ActorEdgeSystem {
        // Parse endpoint
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let host = components.first.map(String.init),
              let port = components.last.flatMap({ Int($0) }) else {
            throw TestServerError.invalidEndpoint
        }

        // Create HTTP/2 client transport with optional TLS
        let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity
        if let tlsConfig = tls {
            transportSecurity = try tlsConfig.toGRPCClientTransportSecurity()
        } else {
            transportSecurity = .plaintext
        }

        // Create client transport with optional HTTP/2 authority for SNI
        var transportConfig = HTTP2ClientTransport.Posix.Config.defaults
        if let tlsConfig = tls, let serverHostname = tlsConfig.serverHostname {
            transportConfig.http2.authority = serverHostname
        }

        let clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: transportSecurity,
            config: transportConfig
        )

        // Create gRPC client
        let grpcClient = GRPCClient(transport: clientTransport)
        self.grpcClient = grpcClient

        // Start runConnections() in background
        let task = Task<Void, Error> {
            do {
                try await grpcClient.runConnections()
            } catch is CancellationError {
                // Expected during test cleanup
                return
            } catch {
                throw error
            }
        }
        self.runConnectionsTask = task

        // Give client time to establish connection
        // TLS/mTLS requires more time for handshake
        let waitTime: Duration = (tls != nil) ? .milliseconds(2000) : .milliseconds(200)
        try await Task.sleep(for: waitTime)

        // Create transport and system
        // startConnections: false because we manage runConnections() manually in tests
        let transport = GRPCTransport(
            client: grpcClient,
            metricsNamespace: configuration.metrics.namespace,
            startConnections: false  // We already started it above
        )

        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }

    /// Stop the client
    public func stop() async {
        // Cancel and wait for the task to complete
        if let task = runConnectionsTask {
            task.cancel()

            // Wait for clean termination
            do {
                try await task.value
            } catch is CancellationError {
                // Expected
            } catch {
                // Log but continue cleanup
                print("Warning: Connection task error during stop: \(error)")
            }
        }

        runConnectionsTask = nil
        grpcClient = nil
    }
}

/// Errors for test server
public enum TestServerError: Error, CustomStringConvertible {
    case serverAlreadyRunning
    case noActorsProvided
    case invalidActorSystem
    case invalidEndpoint

    public var description: String {
        switch self {
        case .serverAlreadyRunning:
            return "Server is already running"
        case .noActorsProvided:
            return "No actors provided to test helper"
        case .invalidActorSystem:
            return "Actor system is not ActorEdgeSystem"
        case .invalidEndpoint:
            return "Invalid endpoint format. Expected 'host:port'"
        }
    }
}
