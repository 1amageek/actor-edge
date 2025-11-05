import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// TRUE Remote Call Integration Tests
/// These tests actually use gRPC transport (unlike the local-only RemoteCallTests)
@Suite("True Remote Call Integration Tests (gRPC)", .serialized)
struct TrueRemoteCallTests {

    @Test("Basic remote call with actual server")
    func testBasicRemoteCall() async throws {
        // Define well-known actor ID
        let actorID = ActorEdgeID("test-actor-1")

        // Create Server instance (same as production)
        let server = SimpleTestServer(
            port: 60001,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )

        // Start server using ServerLifecycleManager
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)

        defer {
            Task {
                try? await lifecycle.stop()
            }
        }

        // Create client (same as production)
        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60001")
        defer { Task { await clientLifecycle.stop() } }

        // Use the actor ID returned from server
        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Test 1: Echo
        let message = TestMessage(content: "Hello!")
        let echoResult = try await remoteActor.echo(message)
        #expect(echoResult.content == "Hello!")

        // Test 2: Increment counter
        let count1 = try await remoteActor.incrementCounter()
        #expect(count1 == 1)

        let count2 = try await remoteActor.incrementCounter()
        #expect(count2 == 2)

        // Test 3: Get counter value
        let finalCount = try await remoteActor.getCounter()
        #expect(finalCount == 2)

        // Cleanup
        try await lifecycle.stop()
    }

    @Test("Complex type serialization over remote transport")
    func testComplexTypeSerialization() async throws {
        let actorID = ActorEdgeID("complex-serialization-actor")

        let server = SimpleTestServer(
            port: 60002,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60002")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        let complexMsg = ComplexMessage(
            timestamp: Date(),
            numbers: [1, 2, 3, 4, 5],
            nested: ComplexMessage.NestedData(
                flag: true,
                values: ["pi": 3.14159, "e": 2.71828]
            ),
            optional: "test value"
        )

        let result = try await remoteActor.complexOperation(complexMsg)

        // Verify processing occurred on server
        #expect(result.numbers == [2, 4, 6, 8, 10])  // Doubled
        #expect(result.nested.flag == false)  // Flipped
        #expect(result.optional == "TEST VALUE")  // Uppercased

        try await lifecycle.stop()
    }

    @Test("Array processing over remote transport")
    func testArrayProcessing() async throws {
        let actorID = ActorEdgeID("array-processing-actor")

        let server = SimpleTestServer(
            port: 60003,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60003")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        let messages = [
            TestMessage(content: "msg1"),
            TestMessage(content: "msg2"),
            TestMessage(content: "msg3")
        ]

        let processed = try await remoteActor.process(messages)
        #expect(processed.count == 3)
        #expect(processed[0].content == "Processed: msg1")
        #expect(processed[1].content == "Processed: msg2")
        #expect(processed[2].content == "Processed: msg3")

        try await lifecycle.stop()
    }

    @Test("Large payload over gRPC (1000 messages)")
    func testLargePayloadOverGRPC() async throws {
        let actorID = ActorEdgeID("large-payload-actor")

        let server = SimpleTestServer(
            port: 60004,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60004")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Create large payload
        let largeArray = (0..<1000).map { i in
            TestMessage(content: "Message \(i)")
        }

        let result = try await remoteActor.process(largeArray)
        #expect(result.count == 1000)
        #expect(result[0].content == "Processed: Message 0")
        #expect(result[500].content == "Processed: Message 500")
        #expect(result[999].content == "Processed: Message 999")

        try await lifecycle.stop()
    }

    @Test("Multiple concurrent gRPC calls")
    func testConcurrentGRPCCalls() async throws {
        let actorID = ActorEdgeID("concurrent-calls-actor")

        let server = SimpleTestServer(
            port: 60005,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60005")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Issue 20 concurrent calls over gRPC
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await remoteActor.incrementCounter()
                }
            }

            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }

            // All calls should succeed
            #expect(results.count == 20)

            // Final counter should be 20
            let finalCount = try await remoteActor.getCounter()
            #expect(finalCount == 20)
        }

        try await lifecycle.stop()
    }

    @Test("Multiple different actors over gRPC")
    func testMultipleActorsOverGRPC() async throws {
        let actorID1 = ActorEdgeID("test-actor")
        let actorID2 = ActorEdgeID("echo-actor")
        let actorID3 = ActorEdgeID("counting-actor")

        let server = SimpleTestServer(
            port: 60006,
            actors: [
                { TestActorImpl(actorSystem: $0) },
                { EchoActorImpl(actorSystem: $0) },
                { CountingActorImpl(actorSystem: $0) }
            ],
            actorIDs: [actorID1, actorID2, actorID3]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60006")
        defer { Task { await clientLifecycle.stop() } }

        // Resolve all actors from client
        let remote1 = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)
        let remote2 = try $EchoActor.resolve(id: serverActorIDs[1], using: clientSystem)
        let remote3 = try $CountingActor.resolve(id: serverActorIDs[2], using: clientSystem)

        // Call each actor via gRPC
        let msg = TestMessage(content: "test")
        let echo1 = try await remote1.echo(msg)
        #expect(echo1.content == "test")

        let echo2 = try await remote2.echoString("hello")
        #expect(echo2 == "hello")

        try await remote3.increment()
        let count = try await remote3.getCount()
        #expect(count == 1)

        try await lifecycle.stop()
    }

    @Test("Void method calls over gRPC")
    func testVoidMethodsOverGRPC() async throws {
        let actorID = ActorEdgeID("stateful-actor")

        let server = SimpleTestServer(
            port: 60007,
            actors: [{ StatefulActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60007")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $StatefulActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Void methods via gRPC
        try await remoteActor.setState("key1", value: "value1")
        try await remoteActor.setState("key2", value: "value2")

        // Verify state
        let value1 = try await remoteActor.getState("key1")
        #expect(value1 == "value1")

        let value2 = try await remoteActor.getState("key2")
        #expect(value2 == "value2")

        try await lifecycle.stop()
    }

    @Test("Connection reuse over gRPC")
    func testConnectionReuseOverGRPC() async throws {
        let actorID = ActorEdgeID("connection-reuse-actor")

        let server = SimpleTestServer(
            port: 60008,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID]
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:60008")
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Make 50 sequential calls - should reuse HTTP/2 connection
        for i in 0..<50 {
            let result = try await remoteActor.incrementCounter()
            #expect(result == i + 1)
        }

        try await lifecycle.stop()
    }
}
