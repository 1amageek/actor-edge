import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore
import ActorRuntime

/// TRUE Remote Error Path Tests
/// These tests verify error handling over actual gRPC transport
@Suite("True Remote Error Path Tests (gRPC)", .serialized)
struct TrueRemoteErrorTests {

    @Test("Remote actor throws error over gRPC")
    func testRemoteActorThrowsErrorOverGRPC() async throws {
        let actorID = ActorEdgeID("error-throwing-actor")

        let server = SimpleTestServer(
            port: 50101,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50101")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Call method that throws - error should propagate over gRPC
        await #expect(throws: RuntimeError.self) {
            try await remoteActor.throwValidationError()
        }

        // Verify we can catch and inspect the error
        do {
            try await remoteActor.throwValidationError()
            Issue.record("Should have thrown error")
        } catch let error as RuntimeError {
            // Error should be wrapped in executionFailed over gRPC
            switch error {
            case .executionFailed(let message, _):
                #expect(message.contains("validationError") || message.contains("Test validation failed"))
            default:
                // May get other error types depending on serialization
                break
            }
        }

        try await lifecycle.stop()
    }

    @Test("Actor not found over gRPC")
    func testActorNotFoundOverGRPC() async throws {
        // Don't register any actors on server
        let server = SimpleTestServer(port: 50102, actors: [])
        let lifecycle = ServerLifecycleManager()
        try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50102")
        defer { Task { await clientLifecycle.stop() } }

        // Try to resolve non-existent actor
        let fakeID = ActorEdgeID("nonexistent-actor")
        let remoteActor = try $TestActor.resolve(id: fakeID, using: clientSystem)

        // Call should fail - actor not found on server
        await #expect(throws: RuntimeError.self) {
            try await remoteActor.incrementCounter()
        }

        do {
            try await remoteActor.incrementCounter()
            Issue.record("Should have thrown actor not found error")
        } catch let error as RuntimeError {
            // Should get actorNotFound or executionFailed from server
            switch error {
            case .actorNotFound:
                // Perfect - exact error
                break
            case .executionFailed:
                // Also acceptable - wrapped error
                break
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        }

        try await lifecycle.stop()
    }

    @Test("Multiple errors in sequence over gRPC")
    func testMultipleErrorsOverGRPC() async throws {
        let actorID = ActorEdgeID("sequential-errors-actor")

        let server = SimpleTestServer(
            port: 50103,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50103")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Make several calls that throw errors
        for _ in 0..<5 {
            await #expect(throws: RuntimeError.self) {
                try await remoteActor.throwValidationError()
            }
        }

        // Verify connection still works after errors
        let result = try await remoteActor.incrementCounter()
        #expect(result == 1)

        try await lifecycle.stop()
    }

    @Test("Concurrent calls with mixed success and errors over gRPC")
    func testConcurrentMixedCallsOverGRPC() async throws {
        let actorID = ActorEdgeID("mixed-calls-actor")

        let server = SimpleTestServer(
            port: 50104,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50104")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        await withThrowingTaskGroup(of: Void.self) { group in
            // Some calls that succeed
            for _ in 0..<10 {
                group.addTask {
                    let _ = try await remoteActor.incrementCounter()
                }
            }

            // Some calls that fail
            for _ in 0..<10 {
                group.addTask {
                    do {
                        try await remoteActor.throwValidationError()
                        Issue.record("Should have thrown")
                    } catch {
                        // Expected
                    }
                }
            }

            // Wait for all to complete
            while let _ = try? await group.next() {
                // Process results
            }
        }

        // Verify final state - only successful calls incremented
        let finalCount = try await remoteActor.getCounter()
        #expect(finalCount == 10)

        try await lifecycle.stop()
    }

    @Test("Connection failure handling", .disabled("Requires server shutdown during test"))
    func testConnectionFailure() async throws {
        // TODO: Implement test that:
        // 1. Starts server
        // 2. Makes successful call
        // 3. Stops server
        // 4. Attempts call and verifies connection error
        // 5. Restarts server
        // 6. Verifies reconnection works
    }

    @Test("Timeout handling", .disabled("Requires slow operation implementation"))
    func testTimeoutHandling() async throws {
        // TODO: Implement test that:
        // 1. Creates actor with very slow operation
        // 2. Configures short timeout on client
        // 3. Verifies timeout error is raised
    }
}
