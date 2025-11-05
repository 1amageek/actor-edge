import Testing
import Foundation
import ActorRuntime
@testable import ActorEdgeCore

/// Basic smoke tests for ActorEdge
@Suite("Basic ActorEdge Tests")
struct BasicTests {

    @Test("ActorEdgeID creation")
    func testActorEdgeIDCreation() {
        let id1 = ActorEdgeID()
        let id2 = ActorEdgeID("custom-id")

        #expect(id1.description.count > 0)
        #expect(id2.description == "ActorEdgeID(custom-id)")
        #expect(id1 != id2)
    }

    @Test("ActorEdgeID equality")
    func testActorEdgeIDEquality() {
        let id1 = ActorEdgeID("test-id")
        let id2 = ActorEdgeID("test-id")
        let id3 = ActorEdgeID("other-id")

        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    @Test("MockDistributedTransport send invocation")
    func testMockTransportSendInvocation() async throws {
        let transport = MockDistributedTransport()
        let invocation = TestHelpers.makeTestInvocation()

        let response = try await transport.sendInvocation(invocation)

        #expect(transport.callCount == 1)
        #expect(transport.lastInvocation?.callID == invocation.callID)
        #expect(response.callID == invocation.callID)
    }

    @Test("MockDistributedTransport error handling")
    func testMockTransportErrorHandling() async throws {
        let transport = MockDistributedTransport()
        transport.shouldThrowError = true
        transport.errorToThrow = RuntimeError.transportFailed("Test error")

        let invocation = TestHelpers.makeTestInvocation()

        do {
            _ = try await transport.sendInvocation(invocation)
            Issue.record("Should have thrown error")
        } catch let error as RuntimeError {
            #expect(error == RuntimeError.transportFailed("Test error"))
        }
    }

    @Test("TestHelpers create invocation envelope")
    func testHelpersCreateInvocation() {
        let invocation = TestHelpers.makeTestInvocation(
            recipientID: "actor-1",
            target: "testMethod"
        )

        #expect(invocation.recipientID == "actor-1")
        #expect(invocation.target == "testMethod")
        #expect(invocation.callID.count > 0)
    }

    @Test("TestHelpers create response envelope")
    func testHelpersCreateResponse() {
        let response = TestHelpers.makeTestResponse(callID: "test-123")

        #expect(response.callID == "test-123")

        switch response.result {
        case .success:
            #expect(Bool(true))
        default:
            Issue.record("Expected success result")
        }
    }

    @Test("TestHelpers create error response")
    func testHelpersCreateErrorResponse() {
        let error = RuntimeError.actorNotFound("actor-1")
        let response = TestHelpers.makeTestErrorResponse(
            callID: "test-123",
            error: error
        )

        #expect(response.callID == "test-123")

        switch response.result {
        case .failure(let err):
            #expect(err == error)
        default:
            Issue.record("Expected failure result")
        }
    }

    @Test("EnvelopeFactory batch creation")
    func testEnvelopeFactoryBatch() {
        let batch = TestHelpers.EnvelopeFactory.batch(count: 5)

        #expect(batch.count == 5)
        #expect(batch[0].target == "method-0")
        #expect(batch[4].target == "method-4")
    }

    @Test("EnvelopeFactory invocation with argument")
    func testEnvelopeFactoryWithArgument() throws {
        struct TestArg: Codable {
            let value: String
        }

        let arg = TestArg(value: "test")
        let invocation = try TestHelpers.EnvelopeFactory.invocationWithArgument(
            arg,
            target: "processTest"
        )

        #expect(invocation.target == "processTest")
        #expect(invocation.arguments.count > 0)

        let decoded = try JSONDecoder().decode(TestArg.self, from: invocation.arguments)
        #expect(decoded.value == "test")
    }

    @Test("EnvelopeFactory response with result")
    func testEnvelopeFactoryWithResult() throws {
        struct TestResult: Codable {
            let status: String
        }

        let result = TestResult(status: "success")
        let response = try TestHelpers.EnvelopeFactory.responseWithResult(
            result,
            callID: "call-123"
        )

        #expect(response.callID == "call-123")

        switch response.result {
        case .success(let data):
            let decoded = try JSONDecoder().decode(TestResult.self, from: data)
            #expect(decoded.status == "success")
        default:
            Issue.record("Expected success result")
        }
    }
}
