import Testing
import Foundation
import ActorRuntime
@testable import ActorEdgeCore
import Distributed

/// Centralized test utilities for ActorEdge
public struct TestHelpers {
    /// Test timeout duration
    public static let testTimeout: Duration = .seconds(30)

    /// Wait for async condition with timeout
    public static func waitForCondition(
        timeout: Duration = testTimeout,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () async throws -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while start.duration(to: ContinuousClock.now) < timeout {
            if try await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("Condition not met within timeout")
    }

    /// Create test invocation envelope
    public static func makeTestInvocation(
        recipientID: String = "test-actor",
        callID: String = UUID().uuidString,
        target: String = "testMethod",
        genericSubstitutions: [String] = [],
        arguments: Data = Data()
    ) -> InvocationEnvelope {
        return InvocationEnvelope(
            callID: callID,
            recipientID: recipientID,
            target: target,
            genericSubstitutions: genericSubstitutions,
            arguments: arguments
        )
    }

    /// Create test response envelope
    public static func makeTestResponse(
        callID: String = UUID().uuidString,
        success: Data = Data()
    ) -> ResponseEnvelope {
        return ResponseEnvelope(
            callID: callID,
            result: .success(success)
        )
    }

    /// Create test error response
    public static func makeTestErrorResponse(
        callID: String = UUID().uuidString,
        error: RuntimeError = .executionFailed("Test error", underlying: "Test")
    ) -> ResponseEnvelope {
        return ResponseEnvelope(
            callID: callID,
            result: .failure(error)
        )
    }

    /// Assert invocation envelope equality
    public static func assertInvocationEqual(
        _ actual: InvocationEnvelope,
        _ expected: InvocationEnvelope,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(actual.callID == expected.callID,
               "CallIDs don't match")
        #expect(actual.recipientID == expected.recipientID,
               "RecipientIDs don't match")
        #expect(actual.target == expected.target,
               "Targets don't match")
        #expect(actual.genericSubstitutions == expected.genericSubstitutions,
               "Generic substitutions don't match")
        #expect(actual.arguments == expected.arguments,
               "Arguments don't match")
    }

    /// Assert response envelope equality
    public static func assertResponseEqual(
        _ actual: ResponseEnvelope,
        _ expected: ResponseEnvelope,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(actual.callID == expected.callID,
               "CallIDs don't match")

        switch (actual.result, expected.result) {
        case (.success(let actualData), .success(let expectedData)):
            #expect(actualData == expectedData, "Success data doesn't match")
        case (.void, .void):
            break
        case (.failure(let actualError), .failure(let expectedError)):
            #expect(actualError == expectedError, "Errors don't match")
        default:
            Issue.record("Result types don't match")
        }
    }

    /// Envelope factory for testing
    public struct EnvelopeFactory {

        /// Create a batch of test invocations
        public static func batch(
            count: Int,
            targetPrefix: String = "method",
            recipientID: String = "test-actor"
        ) -> [InvocationEnvelope] {
            return (0..<count).map { i in
                TestHelpers.makeTestInvocation(
                    recipientID: recipientID,
                    target: "\(targetPrefix)-\(i)"
                )
            }
        }

        /// Create invocation with encoded argument
        public static func invocationWithArgument<T: Codable>(
            _ argument: T,
            recipientID: String = "test-actor",
            target: String = "testMethod"
        ) throws -> InvocationEnvelope {
            let argumentData = try JSONEncoder().encode(argument)
            return InvocationEnvelope(
                callID: UUID().uuidString,
                recipientID: recipientID,
                target: target,
                genericSubstitutions: [],
                arguments: argumentData
            )
        }

        /// Create response with encoded result
        public static func responseWithResult<T: Codable>(
            _ result: T,
            callID: String = UUID().uuidString
        ) throws -> ResponseEnvelope {
            let resultData = try JSONEncoder().encode(result)
            return ResponseEnvelope(
                callID: callID,
                result: .success(resultData)
            )
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    public var timeInterval: TimeInterval {
        let nanoseconds = components.attoseconds / 1_000_000_000
        let seconds = TimeInterval(components.seconds)
        let fractional = TimeInterval(nanoseconds) / 1_000_000_000
        return seconds + fractional
    }
}
