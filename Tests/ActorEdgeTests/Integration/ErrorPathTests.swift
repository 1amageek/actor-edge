import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore
import ActorRuntime

@Suite("Remote Error Path Tests")
struct ErrorPathTests {

    @Test("Remote actor throws custom error")
    func testRemoteActorThrowsCustomError() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Call method that throws
        await #expect(throws: RuntimeError.self) {
            try await resolved.throwValidationError()
        }

        // Verify we can catch and inspect the error
        do {
            try await resolved.throwValidationError()
            Issue.record("Should have thrown error")
        } catch let error as RuntimeError {
            // ActorRuntime wraps custom errors in RuntimeError.executionFailed
            switch error {
            case .executionFailed(let message, _):
                // Verify the error message contains the original error info
                #expect(message.contains("validationError"))
            default:
                Issue.record("Expected executionFailed error")
            }
        }
    }

    @Test("Actor not found error")
    func testActorNotFoundError() async throws {
        let system = ActorEdgeSystem()
        // Don't register any actors

        // Try to resolve non-existent actor
        let fakeID = ActorEdgeID("nonexistent-actor")
        let resolved = try $TestActor.resolve(id: fakeID, using: system)

        // Call should fail - in-process testing means we get transport error
        // since there's no transport configured for truly remote calls
        await #expect(throws: RuntimeError.self) {
            let _ = try await resolved.incrementCounter()
        }

        // Verify error is thrown (specific error type depends on transport config)
        do {
            let _ = try await resolved.incrementCounter()
            Issue.record("Should have thrown error for non-existent actor")
        } catch let error as RuntimeError {
            // In-process testing: we expect transport or actor not found errors
            switch error {
            case .actorNotFound:
                // Expected if actor lookup fails
                break
            case .transportFailed:
                // Expected if no transport configured
                break
            case .executionFailed:
                // May also get execution failed
                break
            default:
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test("Multiple errors in sequence")
    func testMultipleErrorsInSequence() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Make several calls that throw errors
        for _ in 0..<5 {
            await #expect(throws: RuntimeError.self) {
                try await resolved.throwValidationError()
            }
        }

        // Verify connection still works after errors
        let result = try await resolved.incrementCounter()
        #expect(result == 1)
    }

    @Test("Error with concurrent calls")
    func testErrorWithConcurrentCalls() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Mix of successful and failing calls
        await withThrowingTaskGroup(of: Void.self) { group in
            // Some calls that succeed
            for _ in 0..<5 {
                group.addTask {
                    let _ = try await resolved.incrementCounter()
                }
            }

            // Some calls that fail
            for _ in 0..<5 {
                group.addTask {
                    do {
                        try await resolved.throwValidationError()
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

        // Verify final state
        let finalCount = try await resolved.getCounter()
        #expect(finalCount == 5)  // Only successful calls incremented
    }
}
