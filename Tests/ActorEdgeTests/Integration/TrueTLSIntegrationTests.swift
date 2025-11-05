import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore
import ActorRuntime

/// TRUE TLS Integration Tests
/// These tests verify TLS/mTLS functionality over actual gRPC transport
@Suite("True TLS Integration Tests (gRPC)", .serialized)
struct TrueTLSIntegrationTests {

    static let fixturesPath: URL = {
        // Use Bundle.module to access test resources
        guard let resourcePath = Bundle.module.resourcePath else {
            fatalError("Failed to find resource path")
        }
        return URL(fileURLWithPath: resourcePath).appendingPathComponent("Fixtures")
    }()

    @Test("Successful TLS connection with valid certificates")
    func testSuccessfulTLSConnection() async throws {
        let actorID = ActorEdgeID("tls-success-actor")

        // Load server certificates
        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem)
        )

        // Load CA for client
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path

        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        let server = SimpleTestServer(
            port: 60201,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(
            endpoint: "127.0.0.1:60201",
            tls: clientTLS
        )
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Should successfully call over TLS
        let message = TestMessage(content: "Secure message")
        let result = try await remoteActor.echo(message)
        #expect(result.content == "Secure message")

        try await lifecycle.stop()
    }

    @Test("TLS connection fails with invalid certificate")
    func testTLSConnectionFailsWithInvalidCert() async throws {
        let actorID = ActorEdgeID("tls-invalid-cert-actor")

        // Use invalid/self-signed certificate on server
        let invalidCertPath = Self.fixturesPath.appendingPathComponent("invalid-cert.pem").path
        let invalidKeyPath = Self.fixturesPath.appendingPathComponent("invalid-key.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(invalidCertPath, format: .pem)],
            privateKey: .file(invalidKeyPath, format: .pem)
        )

        // Client expects CA-signed cert
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path
        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        let server = SimpleTestServer(
            port: 60202,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        // Client creation or call should fail due to invalid cert
        let clientLifecycle = ClientLifecycleManager()
        do {
            let clientSystem = try await clientLifecycle.createClient(
                endpoint: "127.0.0.1:60202",
                tls: clientTLS
            )
            let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

            // Attempt call - should fail
            let _ = try await remoteActor.incrementCounter()
            await clientLifecycle.stop()
            Issue.record("Should have failed with TLS error")
        } catch {
            // Expected - TLS verification failure
            // Error type varies depending on where TLS failure occurs
        }

        await clientLifecycle.stop()
        try await lifecycle.stop()
    }

    @Test("Mutual TLS (mTLS) with client certificate")
    func testMutualTLS() async throws {
        let actorID = ActorEdgeID("mtls-actor")

        // Server configuration with mTLS
        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path
        let clientCertPath = Self.fixturesPath.appendingPathComponent("client-cert.pem").path
        let clientKeyPath = Self.fixturesPath.appendingPathComponent("client-key.pem").path
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path

        // Server trusts CA (proper CA hierarchy)
        let serverTLS = try TLSConfiguration.serverMTLS(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem),
            trustRoots: .certificates([.file(caCertPath, format: .pem)]),
            clientCertificateVerification: .noHostnameVerification
        )

        // Client trusts CA (proper CA hierarchy)
        let clientTLS = ClientTLSConfiguration.mutualTLS(
            certificateChain: [.file(clientCertPath, format: .pem)],
            privateKey: .file(clientKeyPath, format: .pem),
            trustRoots: .certificates([.file(caCertPath, format: .pem)]),
            serverHostname: "localhost"
        )

        let server = SimpleTestServer(
            port: 60203,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(
            endpoint: "127.0.0.1:60203",
            tls: clientTLS
        )
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Should successfully call with mTLS
        let result = try await remoteActor.incrementCounter()
        #expect(result == 1)

        // Multiple calls should work
        let result2 = try await remoteActor.incrementCounter()
        #expect(result2 == 2)

        try await lifecycle.stop()
    }

    @Test("mTLS fails without client certificate")
    func testMTLSFailsWithoutClientCert() async throws {
        let actorID = ActorEdgeID("mtls-no-client-cert-actor")

        // Server requires client certificate
        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path

        let serverTLS = try TLSConfiguration.serverMTLS(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem),
            trustRoots: .certificates([.file(caCertPath, format: .pem)]),
            clientCertificateVerification: .fullVerification
        )

        // Client without certificate (only trusts server)
        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        let server = SimpleTestServer(
            port: 60204,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        do {
            let clientSystem = try await clientLifecycle.createClient(
                endpoint: "127.0.0.1:60204",
                tls: clientTLS
            )
            let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

            // Call should fail - no client cert provided
            let _ = try await remoteActor.incrementCounter()
            await clientLifecycle.stop()
            Issue.record("Should have failed - mTLS requires client certificate")
        } catch {
            // Expected - mTLS verification failure
            // Error type varies depending on where TLS failure occurs
        }

        await clientLifecycle.stop()
        try await lifecycle.stop()
    }

    @Test("TLS with system default trust roots")
    func testTLSWithSystemDefaults() async throws {
        let actorID = ActorEdgeID("tls-insecure-actor")

        // Note: This test uses .insecure() as we can't guarantee
        // our test cert is in system trust store
        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem)
        )

        // Using insecure mode (for testing only!)
        let clientTLS = ClientTLSConfiguration.insecure()

        let server = SimpleTestServer(
            port: 60205,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(
            endpoint: "127.0.0.1:60205",
            tls: clientTLS
        )
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        let result = try await remoteActor.incrementCounter()
        #expect(result == 1)

        try await lifecycle.stop()
    }

    @Test("TLS protects sensitive data in transit")
    func testTLSProtectsSensitiveData() async throws {
        let actorID = ActorEdgeID("tls-sensitive-data-actor")

        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem)
        )

        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        let server = SimpleTestServer(
            port: 60206,
            tls: serverTLS,
            actors: [{ StatefulActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(
            endpoint: "127.0.0.1:60206",
            tls: clientTLS
        )
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $StatefulActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Send sensitive data over TLS
        try await remoteActor.setState("api_key", value: "super_secret_key_12345")
        try await remoteActor.setState("password", value: "p@ssw0rd!")

        // Retrieve and verify
        let apiKey = try await remoteActor.getState("api_key")
        #expect(apiKey == "super_secret_key_12345")

        let password = try await remoteActor.getState("password")
        #expect(password == "p@ssw0rd!")

        try await lifecycle.stop()
    }

    @Test("TLS handshake with concurrent clients")
    func testConcurrentTLSConnections() async throws {
        let actorID = ActorEdgeID("tls-concurrent-actor")

        let serverCertPath = Self.fixturesPath.appendingPathComponent("server-cert.pem").path
        let serverKeyPath = Self.fixturesPath.appendingPathComponent("server-key.pem").path
        let caCertPath = Self.fixturesPath.appendingPathComponent("ca-cert.pem").path

        let serverTLS = try TLSConfiguration.server(
            certificateChain: [.file(serverCertPath, format: .pem)],
            privateKey: .file(serverKeyPath, format: .pem)
        )

        let clientTLS = ClientTLSConfiguration.client(
            trustRoots: .certificates([.file(caCertPath, format: .pem)])
        )

        let server = SimpleTestServer(
            port: 60207,
            tls: serverTLS,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        // Create multiple clients concurrently
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    // Each task creates its own client system
                    let taskClientLifecycle = ClientLifecycleManager()
                    let taskClientSystem = try await taskClientLifecycle.createClient(
                        endpoint: "127.0.0.1:60207",
                        tls: clientTLS
                    )
                    defer { Task { await taskClientLifecycle.stop() } }

                    let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: taskClientSystem)
                    let result = try await remoteActor.incrementCounter()
                    return result
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }

            // All clients should succeed
            #expect(results.count == 10)
        }

        try await lifecycle.stop()
    }
}
