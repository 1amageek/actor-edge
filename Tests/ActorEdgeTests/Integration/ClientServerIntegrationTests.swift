import Testing
@testable import ActorEdgeCore
import ActorEdgeServer
import ActorEdgeClient
import Distributed

@Suite("Client-Server Integration Tests", .tags(.integration))
struct ClientServerIntegrationTests {
    
    @Test("Basic client-server communication")
    func basicClientServerCommunication() async throws {
        // Force type retention for testing
        TestMessage._forceTypeRetention()
        
        // Use the helper to create connected systems
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["test-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        #expect(testActor.id.value == "test-actor")
        
        // Resolve remote actor from client
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        // Test remote call
        let testMessage = TestMessage(content: "Hello from client!")
        let response = try await remoteActor.echo(testMessage)
        
        #expect(response.content == testMessage.content)
        #expect(response.id == testMessage.id)
    }
    
    @Test("Complex data type communication")
    func complexDataTypeCommunication() async throws {
        ComplexMessage._forceTypeRetention()
        
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["complex-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        let complexMessage = ComplexMessage(
            numbers: [10, 20, 30],
            nested: ComplexMessage.NestedData(
                flag: true,
                values: ["test": 1.23, "value": 4.56]
            ),
            optional: "test_optional"
        )
        
        let result = try await remoteActor.complexOperation(complexMessage)
        
        #expect(result.numbers == [20, 40, 60]) // Doubled
        #expect(result.nested.flag == false) // Inverted
        #expect(result.nested.values["test"] == 2.46) // Doubled
        #expect(result.optional == "TEST_OPTIONAL") // Uppercased
    }
    
    @Test("Array processing communication")
    func arrayProcessingCommunication() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["array-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        let messages = (1...5).map { TestMessage(content: "Message \($0)") }
        let processed = try await remoteActor.process(messages)
        
        #expect(processed.count == messages.count)
        for (index, processedMsg) in processed.enumerated() {
            #expect(processedMsg.content == "Processed: Message \(index + 1)")
            #expect(processedMsg.id.hasSuffix("_processed"))
        }
    }
    
    @Test("Error propagation across network")
    func errorPropagation() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["error-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        // Test generic error
        await #expect(throws: ActorEdgeError.self) {
            try await remoteActor.throwsError()
        }
        
        // Test specific error
        await #expect(throws: TestError.self) {
            try await remoteActor.throwsSpecificError(.networkError)
        }
    }
    
    @Test("Void method calls")
    func voidMethodCalls() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["void-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        // Initial counter should be 0
        let initialCount = try await remoteActor.getCounter()
        #expect(initialCount == 0)
        
        // Call void method multiple times
        try await remoteActor.voidMethod()
        try await remoteActor.voidMethod()
        
        // Counter should have incremented
        let finalCount = try await remoteActor.getCounter()
        #expect(finalCount == 2)
    }
    
    @Test("High concurrency communication", .timeLimit(.minutes(1)))
    func highConcurrencyCommunication() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["concurrent-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        let concurrentCallCount = 50
        let messages = (1...concurrentCallCount).map { 
            TestMessage(content: "Concurrent message \($0)") 
        }
        
        let startTime = ContinuousClock.now
        
        // Execute all calls concurrently
        let results = try await withThrowingTaskGroup(of: TestMessage.self) { group in
            for message in messages {
                group.addTask {
                    try await remoteActor.echo(message)
                }
            }
            
            var responses: [TestMessage] = []
            for try await response in group {
                responses.append(response)
            }
            return responses
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let callsPerSecond = Double(concurrentCallCount) / duration.timeInterval
        
        #expect(results.count == concurrentCallCount)
        
        // Verify all original messages are echoed back
        let originalContents = Set(messages.map { $0.content })
        let responseContents = Set(results.map { $0.content })
        #expect(originalContents == responseContents)
        
        // Performance expectation: at least 25 calls per second
        #expect(callsPerSecond > 25, "Performance too slow: \(callsPerSecond) calls/sec")
    }
    
    @Test("State management across calls")
    func stateManagementAcrossCalls() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["stateful-actor"])
        
        let statefulActor = StatefulActorImpl(actorSystem: server)
        let remoteActor = try $StatefulActor.resolve(id: statefulActor.id, using: client)
        
        // Set some state
        try await remoteActor.setState("key1", value: "value1")
        try await remoteActor.setState("key2", value: "value2")
        
        // Retrieve state
        let value1 = try await remoteActor.getState("key1")
        let value2 = try await remoteActor.getState("key2")
        let value3 = try await remoteActor.getState("nonexistent")
        
        #expect(value1 == "value1")
        #expect(value2 == "value2")
        #expect(value3 == nil)
        
        // Check access count
        let accessCount = try await remoteActor.getAccessCount()
        #expect(accessCount == 5) // 2 sets + 3 gets
        
        // Clear and verify
        try await remoteActor.clearState()
        let clearedValue = try await remoteActor.getState("key1")
        #expect(clearedValue == nil)
    }
    
    @Test("Transport failure recovery")
    func transportFailureRecovery() async throws {
        let mockTransport = MockMessageTransport()
        let system = ActorEdgeSystem(transport: mockTransport, metricsNamespace: "test")
        
        system.setPreAssignedIDs(["test-actor"])
        let actor = TestActorImpl(actorSystem: system)
        
        // Create a remote reference through a client system
        let clientTransport = MockMessageTransport()
        let clientSystem = ActorEdgeSystem(transport: clientTransport, metricsNamespace: "client")
        
        // Set up transport to fail initially
        clientTransport.shouldThrowError = true
        clientTransport.errorToThrow = TransportError.connectionFailed(reason: "Network error")
        
        let remoteActor = try $TestActor.resolve(id: actor.id, using: clientSystem)
        
        // Call should fail
        await #expect(throws: Error.self) {
            try await remoteActor.echo(TestMessage(content: "Test"))
        }
        
        // Reset transport and retry
        clientTransport.shouldThrowError = false
        let testMessage = TestMessage(content: "Recovery test")
        clientTransport.mockResponse = TestHelpers.makeTestEnvelope(
            type: .response,
            payload: try JSONEncoder().encode(testMessage)
        )
        
        // Call should now succeed
        let result = try await remoteActor.echo(testMessage)
        #expect(result.content == testMessage.content)
    }
    
    @Test("Multiple actors on same system")
    func multipleActorsOnSameSystem() async throws {
        // Force type retention
        TestMessage._forceTypeRetention()
        ComplexMessage._forceTypeRetention()
        
        // Create server with multiple actors
        let serverSystem = ActorEdgeSystem(metricsNamespace: "multi_actor_server")
        serverSystem.setPreAssignedIDs(["actor1", "actor2", "actor3"])
        
        let actor1 = TestActorImpl(actorSystem: serverSystem)
        let actor2 = ComplexTestActorImpl(actorSystem: serverSystem)
        let actor3 = CountingActorImpl(actorSystem: serverSystem)
        
        // Test local access
        let echo = try await actor1.echo(TestMessage(content: "test"))
        #expect(echo.content == "test")
        
        let complex = try await actor2.processComplex(ComplexMessage())
        #expect(complex.numbers.contains(999)) // Check for marker
        
        try await actor3.increment()
        let count = try await actor3.getCount()
        #expect(count == 1)
    }
    
    @Test("Actor not found error")
    func actorNotFoundError() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        
        // Try to resolve non-existent actor
        let nonExistentID = ActorEdgeID("non-existent-actor")
        let remoteActor = try $TestActor.resolve(id: nonExistentID, using: client)
        
        // Should throw actor not found error when trying to call
        await #expect(throws: Error.self) {
            _ = try await remoteActor.echo(TestMessage(content: "test"))
        }
    }
    
    @Test("Large message transfer")
    func largeMessageTransfer() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["large-message-actor"])
        
        let testActor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: testActor.id, using: client)
        
        // Create a large message (1MB of data)
        let largeContent = String(repeating: "A", count: 1024 * 1024)
        let largeMessage = TestMessage(content: largeContent)
        
        let response = try await remoteActor.echo(largeMessage)
        #expect(response.content.count == largeContent.count)
        #expect(response.content == largeContent)
    }
    
    @Test("Actor lifecycle and cleanup")
    func actorLifecycleAndCleanup() async throws {
        // Test actor creation, usage, and cleanup
        let serverSystem = ActorEdgeSystem(metricsNamespace: "lifecycle_server")
        let actorID = ActorEdgeID("lifecycle-actor")
        serverSystem.setPreAssignedIDs([actorID.value])
        
        // Create actor
        let actor = TestActorImpl(actorSystem: serverSystem)
        #expect(actor.id.value == actorID.value)
        
        // Verify actor is registered
        let foundActor = serverSystem.findActor(id: actorID)
        #expect(foundActor != nil)
        
        // Use the actor
        let result = try await actor.echo(TestMessage(content: "lifecycle"))
        #expect(result.content == "lifecycle")
        
        // Increment counter
        let count = try await actor.incrementCounter()
        #expect(count == 1)
        
        // Actor cleanup happens automatically when it goes out of scope
    }
    
    @Test("Batch processing")
    func batchProcessing() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["batch-actor"])
        
        let complexActor = ComplexTestActorImpl(actorSystem: server)
        let remoteActor = try $ComplexTestActor.resolve(id: complexActor.id, using: client)
        
        let messages = (1...10).map { TestMessage(content: "Batch item \($0)") }
        let results = try await remoteActor.batchProcess(messages)
        
        #expect(results.count == messages.count)
        for result in results {
            #expect(result.content.hasPrefix("Batch: "))
        }
    }
}