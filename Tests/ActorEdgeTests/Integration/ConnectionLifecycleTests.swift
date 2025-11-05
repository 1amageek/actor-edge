import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore
@testable import ActorEdgeClient
import ActorRuntime

/// Connection Lifecycle Tests
/// These tests verify proper connection management and resource cleanup
@Suite("Connection Lifecycle Tests", .serialized)
struct ConnectionLifecycleTests {

    @Test("Client connects and disconnects cleanly")
    func testConnectionLifecycle() async throws {
        let actorID = ActorEdgeID("lifecycle-test-actor")

        let server = SimpleTestServer(
            port: 60210,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        // Create client with automatic connection management
        let system = try await ActorEdgeSystem.grpcClient(
            endpoint: "127.0.0.1:60210"
        )

        // Verify connection works
        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: system)
        let result = try await remoteActor.incrementCounter()
        #expect(result == 1)

        // Shutdown cleanly
        try await system.shutdown()

        // Give time for shutdown to complete
        try await Task.sleep(for: .milliseconds(200))

        try await lifecycle.stop()
    }

    @Test("Multiple sequential connections to same endpoint")
    func testSequentialConnections() async throws {
        let actorID = ActorEdgeID("sequential-test-actor")

        let server = SimpleTestServer(
            port: 60211,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        // First connection
        let system1 = try await ActorEdgeSystem.grpcClient(endpoint: "127.0.0.1:60211")
        let actor1 = try $TestActor.resolve(id: serverActorIDs[0], using: system1)
        _ = try await actor1.incrementCounter()
        try await system1.shutdown()

        // Second connection (should work after first is shut down)
        let system2 = try await ActorEdgeSystem.grpcClient(endpoint: "127.0.0.1:60211")
        let actor2 = try $TestActor.resolve(id: serverActorIDs[0], using: system2)
        let count1 = try await actor2.getCounter()
        #expect(count1 == 1)  // Counter persisted on server from first connection
        let count2 = try await actor2.incrementCounter()
        #expect(count2 == 2)  // Second increment
        try await system2.shutdown()

        try await lifecycle.stop()
    }

    @Test("Connection survives multiple rapid calls")
    func testConnectionResilience() async throws {
        let actorID = ActorEdgeID("resilience-test-actor")

        let server = SimpleTestServer(
            port: 60212,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let system = try await ActorEdgeSystem.grpcClient(endpoint: "127.0.0.1:60212")
        defer { Task { try? await system.shutdown() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: system)

        // Make many rapid calls
        for _ in 0..<50 {
            _ = try await remoteActor.incrementCounter()
        }

        let finalCount = try await remoteActor.getCounter()
        #expect(finalCount == 50)

        try await system.shutdown()
        try await lifecycle.stop()
    }

    @Test("Shutdown is idempotent")
    func testIdempotentShutdown() async throws {
        let actorID = ActorEdgeID("idempotent-test-actor")

        let server = SimpleTestServer(
            port: 60213,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        _ = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let system = try await ActorEdgeSystem.grpcClient(endpoint: "127.0.0.1:60213")

        // First shutdown
        try await system.shutdown()

        // Second shutdown (should not throw)
        try await system.shutdown()

        // Third shutdown (still should not throw)
        try await system.shutdown()

        try await lifecycle.stop()
    }

    @Test("Connection Manager pattern works correctly")
    func testConnectionManagerPattern() async throws {
        actor ConnectionManager {
            private var system: ActorEdgeSystem?
            private let endpoint: String

            init(endpoint: String) {
                self.endpoint = endpoint
            }

            func connect() async throws -> ActorEdgeSystem {
                if let existing = system {
                    return existing
                }

                let newSystem = try await ActorEdgeSystem.grpcClient(endpoint: endpoint)
                system = newSystem
                return newSystem
            }

            func shutdown() async throws {
                guard let system = system else { return }
                try await system.shutdown()
                self.system = nil
            }
        }

        let actorID = ActorEdgeID("connection-manager-test-actor")

        let server = SimpleTestServer(
            port: 60214,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let connectionManager = ConnectionManager(endpoint: "127.0.0.1:60214")

        // First connect
        let system1 = try await connectionManager.connect()
        let actor1 = try $TestActor.resolve(id: serverActorIDs[0], using: system1)
        _ = try await actor1.incrementCounter()

        // Second connect (should reuse existing)
        let system2 = try await connectionManager.connect()
        let actor2 = try $TestActor.resolve(id: serverActorIDs[0], using: system2)
        let count = try await actor2.getCounter()
        #expect(count == 1)

        // Verify it's the same system
        #expect(system1 === system2)

        // Shutdown
        try await connectionManager.shutdown()

        // Connect again after shutdown
        let system3 = try await connectionManager.connect()
        #expect(system3 !== system1)  // Should be a new system

        try await connectionManager.shutdown()
        try await lifecycle.stop()
    }

    @Test("TLS connection lifecycle")
    func testTLSConnectionLifecycle() async throws {
        let actorID = ActorEdgeID("tls-lifecycle-actor")

        let fixturesPath = URL(fileURLWithPath: Bundle.module.resourcePath!)
            .appendingPathComponent("Fixtures")
        let serverCertPath = fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = fixturesPath.appendingPathComponent("server-key.pem").path
        let caCertPath = fixturesPath.appendingPathComponent("ca-cert.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem)
        )

        let server = SimpleTestServer(
            port: 60215,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        // Create TLS client
        let system = try await ActorEdgeSystem.grpcClient(
            endpoint: "127.0.0.1:60215",
            tls: clientTLS
        )

        // Verify TLS connection works
        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: system)
        let result = try await remoteActor.incrementCounter()
        #expect(result == 1)

        // Shutdown TLS connection
        try await system.shutdown()

        try await lifecycle.stop()
    }
}
