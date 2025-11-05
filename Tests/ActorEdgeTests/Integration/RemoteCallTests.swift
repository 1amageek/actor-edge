import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

@Suite("Remote Call Integration Tests")
struct RemoteCallTests {

    @Test("Basic remote call round-trip")
    func testBasicRemoteCallRoundTrip() async throws {
        // Create system with test actor
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)
        let actorID = testActor.id

        // Resolve actor using protocol
        let resolved = try $TestActor.resolve(id: actorID, using: system)

        // Test 1: Simple echo
        let message = TestMessage(content: "Hello from remote!")
        let echoResult = try await resolved.echo(message)
        #expect(echoResult.content == "Hello from remote!")

        // Test 2: Counter increment
        let count1 = try await resolved.incrementCounter()
        #expect(count1 == 1)

        let count2 = try await resolved.incrementCounter()
        #expect(count2 == 2)

        // Test 3: Process array
        let messages = [
            TestMessage(content: "msg1"),
            TestMessage(content: "msg2"),
            TestMessage(content: "msg3")
        ]
        let processed = try await resolved.process(messages)
        #expect(processed.count == 3)
        #expect(processed[0].content == "Processed: msg1")
    }

    @Test("Multiple concurrent remote calls")
    func testMultipleConcurrentRemoteCalls() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)
        let actorID = testActor.id

        let resolved = try $TestActor.resolve(id: actorID, using: system)

        // Issue 10 concurrent calls
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await resolved.incrementCounter()
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }

            // All calls should succeed
            #expect(results.count == 10)
            // Final counter should be 10
            let finalCount = try await resolved.getCounter()
            #expect(finalCount == 10)
        }
    }

    @Test("Complex type serialization")
    func testComplexTypeSerialization() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Test complex nested structure
        let complexMsg = ComplexMessage(
            timestamp: Date(),
            numbers: [1, 2, 3, 4, 5],
            nested: ComplexMessage.NestedData(
                flag: true,
                values: ["pi": 3.14159, "e": 2.71828]
            ),
            optional: "test value"
        )

        let result = try await resolved.complexOperation(complexMsg)

        // Verify processing occurred
        #expect(result.numbers == [2, 4, 6, 8, 10]) // Doubled
        #expect(result.nested.flag == false) // Flipped
        #expect(result.optional == "TEST VALUE") // Uppercased
    }

    @Test("Void method calls")
    func testVoidMethodCalls() async throws {
        let system = ActorEdgeSystem()
        let testActor = StatefulActorImpl(actorSystem: system)

        let resolved = try $StatefulActor.resolve(id: testActor.id, using: system)

        // Set state (void method)
        try await resolved.setState("key1", value: "value1")
        try await resolved.setState("key2", value: "value2")

        // Verify state was set
        let value1 = try await resolved.getState("key1")
        #expect(value1 == "value1")

        let value2 = try await resolved.getState("key2")
        #expect(value2 == "value2")
    }

    @Test("Large payload")
    func testLargePayload() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Create large payload (1000 messages)
        let largeArray = (0..<1000).map { i in
            TestMessage(content: "Message \(i)")
        }

        let result = try await resolved.process(largeArray)
        #expect(result.count == 1000)
        #expect(result[0].content == "Processed: Message 0")
        #expect(result[999].content == "Processed: Message 999")
    }

    @Test("Multiple different actors")
    func testMultipleActors() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)
        let echoActor = EchoActorImpl(actorSystem: system)
        let countingActor = CountingActorImpl(actorSystem: system)

        // Resolve all three actors
        let remote1 = try $TestActor.resolve(id: testActor.id, using: system)
        let remote2 = try $EchoActor.resolve(id: echoActor.id, using: system)
        let remote3 = try $CountingActor.resolve(id: countingActor.id, using: system)

        // Call each actor
        let msg = TestMessage(content: "test")
        let echo1 = try await remote1.echo(msg)
        #expect(echo1.content == "test")

        let echo2 = try await remote2.echoString("hello")
        #expect(echo2 == "hello")

        try await remote3.increment()
        let count = try await remote3.getCount()
        #expect(count == 1)
    }

    @Test("Connection reuse simulation")
    func testConnectionReuse() async throws {
        let system = ActorEdgeSystem()
        let testActor = TestActorImpl(actorSystem: system)

        let resolved = try $TestActor.resolve(id: testActor.id, using: system)

        // Make 100 sequential calls - same actor instance
        for i in 0..<100 {
            let result = try await resolved.incrementCounter()
            #expect(result == i + 1)
        }
    }
}
