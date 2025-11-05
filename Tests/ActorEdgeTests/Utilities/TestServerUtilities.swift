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
                print("🟠 [ServerLifecycleManager] ServiceGroup.run() starting...")
                try await group.run()
                print("🟠 [ServerLifecycleManager] ServiceGroup.run() completed")
            } catch {
                print("🔴 [ServerLifecycleManager] ServiceGroup.run() error: \(error)")
                // Server stopped (expected during shutdown)
            }
        }

        // Wait for server to be ready by checking listeningAddress
        print("🟠 [ServerLifecycleManager] Waiting for gRPC server to start listening on port \(server.port)...")
        var attempts = 0
        let maxAttempts = 50 // 5 seconds max (50 * 100ms)

        while attempts < maxAttempts {
            if let address = await service.listeningAddress {
                print("🟢 [ServerLifecycleManager] Server is listening on \(address)")
                break
            }
            try await Task.sleep(for: .milliseconds(100))
            attempts += 1

            if attempts % 10 == 0 {
                print("🟠 [ServerLifecycleManager] Still waiting... (attempt \(attempts)/\(maxAttempts))")
            }
        }

        if await service.listeningAddress == nil {
            print("🔴 [ServerLifecycleManager] WARNING: Server did not start listening after \(attempts * 100)ms")
        }

        // Store and return actor IDs from server
        self.actorIDs = server.actorIDs
        print("🟠 [ServerLifecycleManager] Returning actor IDs: \(server.actorIDs.map { "'\($0.value)'" })")
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
        print("🔷 [ClientLifecycleManager] Creating client for endpoint '\(endpoint)'")

        // Parse endpoint
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let host = components.first.map(String.init),
              let port = components.last.flatMap({ Int($0) }) else {
            throw TestServerError.invalidEndpoint
        }

        print("🔷 [ClientLifecycleManager] Parsed host='\(host)', port=\(port)")

        // Create HTTP/2 client transport with optional TLS
        let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity
        if let tlsConfig = tls {
            transportSecurity = try tlsConfig.toGRPCClientTransportSecurity()
            print("🔷 [ClientLifecycleManager] Using TLS")
        } else {
            transportSecurity = .plaintext
            print("🔷 [ClientLifecycleManager] Using plaintext (no TLS)")
        }

        let clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: transportSecurity
        )

        // Create gRPC client
        let grpcClient = GRPCClient(transport: clientTransport)
        self.grpcClient = grpcClient
        print("🔷 [ClientLifecycleManager] GRPCClient created")

        // Start runConnections() in background
        print("🔷 [ClientLifecycleManager] Starting runConnections() in background...")
        let task = Task {
            do {
                try await grpcClient.runConnections()
                print("🔷 [ClientLifecycleManager] runConnections() completed")
            } catch {
                print("🔴 [ClientLifecycleManager] runConnections() error: \(error)")
                throw error
            }
        }
        self.runConnectionsTask = task

        // Give client time to establish connection
        try await Task.sleep(for: .milliseconds(100))
        print("🔷 [ClientLifecycleManager] Client connections started")

        // Create transport and system
        let transport = GRPCTransport(
            client: grpcClient,
            metricsNamespace: configuration.metrics.namespace
        )

        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }

    /// Stop the client
    public func stop() async {
        runConnectionsTask?.cancel()
        runConnectionsTask = nil
        grpcClient = nil
        print("🔷 [ClientLifecycleManager] Client stopped")
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
