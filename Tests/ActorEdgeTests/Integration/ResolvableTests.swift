import Testing
import Foundation
import ActorRuntime
@testable import ActorEdgeCore
import Distributed

/// Tests for @Resolvable protocol-based distributed actor resolution (SE-0428)
///
/// These tests verify that:
/// 1. Protocol-based actor resolution works with $Protocol.resolve()
/// 2. Client code doesn't need to know concrete implementation types
/// 3. Distributed calls through protocol references work correctly
/// 4. Type erasure and protocol conformance work as expected
@Suite("@Resolvable Protocol Tests", .serialized)
struct ResolvableTests {

    // MARK: - Basic Protocol Resolution Tests

    @Test("Resolve TestActor protocol locally")
    func testResolveTestActorProtocolLocally() async throws {
        // Create a single actor system (simulating same-process actors)
        let system = ActorEdgeSystem(configuration: .default)

        // Create actual actor
        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub - this demonstrates SE-0428 feature
        // Client doesn't need to know about TestActorImpl
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Call through protocol - in same system, this is a local call
        let message = TestMessage(content: "Hello")
        let response = try await protocolActor.echo(message)

        #expect(response.content == "Hello")
    }

    @Test("Resolve EchoActor protocol locally")
    func testResolveEchoActorProtocolLocally() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = EchoActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $EchoActor.resolve(id: actorID, using: system)

        // Test string echo
        let stringResult = try await protocolActor.echoString("test")
        #expect(stringResult == "test")

        // Test array echo
        let arrayResult = try await protocolActor.echoArray(["a", "b", "c"])
        #expect(arrayResult == ["a", "b", "c"])
    }

    @Test("Resolve StatefulActor protocol locally")
    func testResolveStatefulActorProtocolLocally() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = StatefulActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $StatefulActor.resolve(id: actorID, using: system)

        // Test state operations
        try await protocolActor.setState("key1", value: "value1")
        let value = try await protocolActor.getState("key1")
        #expect(value == "value1")

        let count = try await protocolActor.getAccessCount()
        #expect(count == 2) // setState + getState
    }

    @Test("Resolve CountingActor protocol locally")
    func testResolveCountingActorProtocolLocally() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = CountingActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $CountingActor.resolve(id: actorID, using: system)

        // Test counting operations
        try await protocolActor.increment()
        try await protocolActor.increment()
        try await protocolActor.increment()

        let count = try await protocolActor.getCount()
        #expect(count == 3)

        try await protocolActor.decrement()
        let countAfterDecrement = try await protocolActor.getCount()
        #expect(countAfterDecrement == 2)

        try await protocolActor.reset()
        let countAfterReset = try await protocolActor.getCount()
        #expect(countAfterReset == 0)
    }

    // MARK: - Complex Type Tests

    @Test("Protocol reference handles complex message types")
    func testProtocolWithComplexMessages() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Create complex message
        let complexMsg = ComplexMessage(
            timestamp: Date(),
            numbers: [1, 2, 3],
            nested: ComplexMessage.NestedData(
                flag: true,
                values: ["pi": 3.14, "e": 2.71]
            ),
            optional: "test"
        )

        // Call through protocol stub
        let result = try await protocolActor.complexOperation(complexMsg)

        // Verify processing occurred
        #expect(result.numbers == [2, 4, 6]) // Doubled
        #expect(result.nested.flag == false) // Flipped
        #expect(result.optional == "TEST") // Uppercased
    }

    @Test("Protocol reference handles array processing")
    func testProtocolWithArrayProcessing() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Process array of messages
        let messages = [
            TestMessage(content: "msg1"),
            TestMessage(content: "msg2"),
            TestMessage(content: "msg3")
        ]

        let results = try await protocolActor.process(messages)

        #expect(results.count == 3)
        #expect(results[0].content == "Processed: msg1")
        #expect(results[1].content == "Processed: msg2")
        #expect(results[2].content == "Processed: msg3")
    }

    // MARK: - Error Handling Tests

    @Test("Protocol reference preserves RuntimeError from actor")
    func testProtocolPreservesRuntimeError() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Test RuntimeError is preserved
        do {
            try await protocolActor.throwsError()
            Issue.record("Should have thrown RuntimeError.timeout")
        } catch let error as RuntimeError {
            // Verify error type is preserved (Issue #24 fix)
            switch error {
            case .timeout(let seconds):
                #expect(seconds == 30)
            default:
                Issue.record("Expected RuntimeError.timeout, got \(error)")
            }
        }
    }

    @Test("Protocol reference preserves custom error types")
    func testProtocolPreservesCustomErrors() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Test custom error is preserved
        let expectedError = TestError.validationError(field: "username", message: "too short")

        do {
            try await protocolActor.throwsSpecificError(expectedError)
            Issue.record("Should have thrown error")
        } catch let runtimeError as RuntimeError {
            // ActorRuntime wraps custom errors in RuntimeError.executionFailed
            switch runtimeError {
            case .executionFailed(let message, _):
                // Verify the error message contains the original error info
                #expect(message.contains("validationError"))
                #expect(message.contains("username"))
                #expect(message.contains("too short"))
            default:
                Issue.record("Expected RuntimeError.executionFailed, got \(runtimeError)")
            }
        } catch {
            Issue.record("Expected RuntimeError wrapping TestError, got \(error)")
        }
    }

    // MARK: - Void Method Tests

    @Test("Protocol reference handles void methods correctly")
    func testProtocolWithVoidMethods() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Get initial counter
        let initialCount = try await protocolActor.getCounter()
        #expect(initialCount == 0)

        // Call void method multiple times
        try await protocolActor.voidMethod()
        try await protocolActor.voidMethod()
        try await protocolActor.voidMethod()

        // Verify side effects occurred
        let finalCount = try await protocolActor.getCounter()
        #expect(finalCount == 3)
    }

    // MARK: - Multiple Protocol Resolution Tests

    @Test("Resolve multiple different protocol types")
    func testMultipleProtocolResolution() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        // Create multiple actors of different types
        let testActor = TestActorImpl(actorSystem: system)
        let echoActor = EchoActorImpl(actorSystem: system)
        let countingActor = CountingActorImpl(actorSystem: system)

        // Resolve all using protocol stubs
        let testProtocol = try $TestActor.resolve(id: testActor.id, using: system)
        let echoProtocol = try $EchoActor.resolve(id: echoActor.id, using: system)
        let countingProtocol = try $CountingActor.resolve(id: countingActor.id, using: system)

        // Use all concurrently
        async let testResult = testProtocol.echo(TestMessage(content: "test"))
        async let echoResult = echoProtocol.echoString("echo")
        async let _: Void = countingProtocol.increment()

        // Wait for all
        let (test, echo, _) = try await (testResult, echoResult, ())

        #expect(test.content == "test")
        #expect(echo == "echo")

        let count = try await countingProtocol.getCount()
        #expect(count == 1)
    }

    @Test("Resolve same actor through protocol multiple times")
    func testSameActorMultipleResolutions() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve same actor multiple times through protocol
        let stub1 = try $TestActor.resolve(id: actorID, using: system)
        let stub2 = try $TestActor.resolve(id: actorID, using: system)

        // Both references should work and affect same actor state
        let count1 = try await stub1.incrementCounter()
        #expect(count1 == 1)

        let count2 = try await stub2.incrementCounter()
        #expect(count2 == 2)

        let count3 = try await stub1.getCounter()
        #expect(count3 == 2)
    }

    // MARK: - Real-world Scenario Tests

    @Test("Client without implementation knowledge can use actor")
    func testClientWithoutImplementationKnowledge() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        // Simulate server creating actor and sending ID to client
        let serverActor = StatefulActorImpl(actorSystem: system)
        let actorIDFromServer = serverActor.id

        // Client only knows protocol, not StatefulActorImpl
        // This is the key benefit of @Resolvable (SE-0428)
        func clientCode(actorID: ActorEdgeID, system: ActorEdgeSystem) async throws {
            // No import of StatefulActorImpl needed!
            let actor = try $StatefulActor.resolve(id: actorID, using: system)

            try await actor.setState("client-key", value: "client-value")
            let value = try await actor.getState("client-key")
            #expect(value == "client-value")
        }

        try await clientCode(actorID: actorIDFromServer, system: system)
    }

    @Test("Protocol reference works with type-specific methods")
    func testProtocolWithTypeSpecificMethods() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = EchoActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve using protocol stub
        let protocolActor = try $EchoActor.resolve(id: actorID, using: system)

        // Test type-specific method with String
        let stringResult = try await protocolActor.echoString("type-specific test")
        #expect(stringResult == "type-specific test")

        // Test type-specific method with Int
        let intResult = try await protocolActor.echoInt(42)
        #expect(intResult == 42)

        // Test type-specific method with custom type
        let message = TestMessage(content: "type-specific message")
        let messageResult = try await protocolActor.echoMessage(message)
        #expect(messageResult.content == "type-specific message")

        // Test array echo
        let arrayResult = try await protocolActor.echoArray(["a", "b", "c"])
        #expect(arrayResult == ["a", "b", "c"])
    }

    // MARK: - Type Erasure Tests

    @Test("Type-erased protocol reference works")
    func testTypeErasedProtocolReference() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        let actualActor = TestActorImpl(actorSystem: system)
        let actorID = actualActor.id

        // Resolve and store in type-erased container
        let protocolActor = try $TestActor.resolve(id: actorID, using: system)

        // Function that accepts any TestActor protocol (type-erased)
        func processWithAnyTestActor(_ actor: any TestActor) async throws -> Int {
            return try await actor.incrementCounter()
        }

        let result = try await processWithAnyTestActor(protocolActor)
        #expect(result == 1)
    }

    @Test("Array of protocol references")
    func testArrayOfProtocolReferences() async throws {
        let system = ActorEdgeSystem(configuration: .default)

        // Create multiple actors
        let actor1 = CountingActorImpl(actorSystem: system)
        let actor2 = CountingActorImpl(actorSystem: system)
        let actor3 = CountingActorImpl(actorSystem: system)

        // Resolve all as protocol references
        let actors: [any CountingActor] = [
            try $CountingActor.resolve(id: actor1.id, using: system),
            try $CountingActor.resolve(id: actor2.id, using: system),
            try $CountingActor.resolve(id: actor3.id, using: system)
        ]

        // Increment all
        for actor in actors {
            try await actor.increment()
        }

        // Verify all were incremented
        for actor in actors {
            let count = try await actor.getCount()
            #expect(count == 1)
        }
    }
}
