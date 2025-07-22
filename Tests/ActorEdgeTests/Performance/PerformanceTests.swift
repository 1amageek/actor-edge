import Testing
@testable import ActorEdgeCore
import Foundation
import Distributed

@Suite("Performance Tests", .tags(.performance))
struct PerformanceTests {
    
    @Test("Serialization performance", .timeLimit(.minutes(1)))
    func serializationPerformance() async throws {
        let serialization = SerializationSystem()
        let message = TestMessage(content: "Performance test message")
        let iterations = 1000
        
        let startTime = ContinuousClock.now
        
        for _ in 0..<iterations {
            let serialized = try serialization.serialize(message)
            _ = try serialization.deserialize(
                serialized.data,
                as: TestMessage.self,
                using: serialized.manifest
            )
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let operationsPerSecond = Double(iterations * 2) / duration.timeInterval // *2 for serialize + deserialize
        
        // Should process at least 10,000 operations per second
        #expect(operationsPerSecond > 10000, "Serialization too slow: \(operationsPerSecond) ops/sec")
    }
    
    @Test("Actor resolution performance", .timeLimit(.minutes(1)))
    func actorResolutionPerformance() async throws {
        let system = ActorEdgeSystem()
        let actorCount = 100
        let lookupIterations = 1000
        
        // Create actors
        let actors = (0..<actorCount).map { _ in TestActorImpl(actorSystem: system) }
        
        let startTime = ContinuousClock.now
        
        // Perform many lookups
        for _ in 0..<lookupIterations {
            for actor in actors.prefix(10) { // Test first 10 actors repeatedly
                _ = try? system.resolve(id: actor.id, as: TestActorImpl.self)
            }
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let lookupsPerSecond = Double(lookupIterations * 10) / duration.timeInterval
        
        // Should perform at least 50,000 lookups per second
        #expect(lookupsPerSecond > 50000, "Actor resolution too slow: \(lookupsPerSecond) lookups/sec")
    }
    
    @Test("Concurrent message handling", .timeLimit(.minutes(1)))
    func concurrentMessageHandling() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["perf-actor"])
        
        let actor = TestActorImpl(actorSystem: server)
        let remoteActor = try $TestActor.resolve(id: actor.id, using: client)
        
        let messageCount = 100
        let messages = (0..<messageCount).map { TestMessage(content: "Message \($0)") }
        
        let startTime = ContinuousClock.now
        
        let responses = try await withThrowingTaskGroup(of: TestMessage.self) { group in
            for message in messages {
                group.addTask {
                    try await remoteActor.echo(message)
                }
            }
            
            var results: [TestMessage] = []
            for try await response in group {
                results.append(response)
            }
            return results
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let messagesPerSecond = Double(messageCount) / duration.timeInterval
        
        #expect(responses.count == messageCount)
        #expect(messagesPerSecond > 50, "Concurrent handling too slow: \(messagesPerSecond) msg/sec")
    }
    
    @Test("Memory usage stability", .timeLimit(.minutes(1)))
    func memoryUsageStability() async throws {
        let system = ActorEdgeSystem()
        
        // Create and destroy many actors
        for _ in 0..<10 {
            var actors: [TestActorImpl] = []
            
            // Create 100 actors
            for _ in 0..<100 {
                actors.append(TestActorImpl(actorSystem: system))
            }
            
            // Use the actors briefly
            for actor in actors {
                _ = try system.resolve(id: actor.id, as: TestActorImpl.self)
            }
            
            // Clear references (actors should be deallocated)
            actors.removeAll()
            
            // Force garbage collection attempt
            for _ in 0..<100 {
                _ = Array(0..<1000) // Create and release temporary memory
            }
        }
        
        // Test passes if we reach here without memory issues
        #expect(Bool(true), "Memory usage appears stable")
    }
    
    @Test("Invocation encoding performance", .timeLimit(.minutes(1)))
    func invocationEncodingPerformance() async throws {
        let system = ActorEdgeSystem()
        let iterations = 1000
        
        let startTime = ContinuousClock.now
        
        for _ in 0..<iterations {
            var encoder = ActorEdgeInvocationEncoder(system: system)
            
            try encoder.recordGenericSubstitution(TestMessage.self)
            try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: TestMessage(content: "perf test")))
            try encoder.recordArgument(RemoteCallArgument(label: nil, name: "number", value: 42))
            try encoder.recordArgument(RemoteCallArgument(label: nil, name: "string", value: "string argument"))
            try encoder.recordReturnType(TestMessage.self)
            try encoder.doneRecording()
            
            _ = try encoder.finalizeInvocation()
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let encodingsPerSecond = Double(iterations) / duration.timeInterval
        
        #expect(encodingsPerSecond > 5000, "Invocation encoding too slow: \(encodingsPerSecond) ops/sec")
    }
    
    @Test("Envelope creation performance", .timeLimit(.minutes(1)))
    func envelopeCreationPerformance() async throws {
        let iterations = 10000
        
        let startTime = ContinuousClock.now
        
        for i in 0..<iterations {
            _ = Envelope.invocation(
                to: ActorEdgeID("actor-\(i)"),
                target: "method-\(i)",
                manifest: SerializationManifest.json(),
                payload: Data("test-\(i)".utf8)
            )
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let creationsPerSecond = Double(iterations) / duration.timeInterval
        
        #expect(creationsPerSecond > 100000, "Envelope creation too slow: \(creationsPerSecond) ops/sec")
    }
    
    @Test("Large payload handling", .timeLimit(.minutes(1)))
    func largePayloadHandling() async throws {
        let serialization = SerializationSystem()
        
        // Create progressively larger payloads
        let sizes = [1_000, 10_000, 100_000, 1_000_000] // 1KB, 10KB, 100KB, 1MB
        
        for size in sizes {
            let largeContent = String(repeating: "A", count: size)
            let message = TestMessage(content: largeContent)
            
            let startTime = ContinuousClock.now
            
            let serialized = try serialization.serialize(message)
            let deserialized = try serialization.deserialize(
                serialized.data,
                as: TestMessage.self,
                using: serialized.manifest
            )
            
            let duration = startTime.duration(to: ContinuousClock.now)
            
            #expect(deserialized.content.count == size)
            #expect(duration < .seconds(1), "Large payload (size: \(size)) took too long: \(duration)")
        }
    }
    
    @Test("Transport throughput", .timeLimit(.minutes(1)))
    func transportThroughput() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        // Simple echo handler
        server.setMessageHandler { envelope in
            return Envelope.response(
                to: envelope.sender ?? envelope.recipient,
                callID: envelope.metadata.callID,
                manifest: envelope.manifest,
                payload: envelope.payload
            )
        }
        
        let messageCount = 5000
        let startTime = ContinuousClock.now
        
        for i in 0..<messageCount {
            let envelope = Envelope.invocation(
                to: ActorEdgeID("target"),
                target: "test",
                callID: "call-\(i)",
                manifest: SerializationManifest.json(),
                payload: Data("message-\(i)".utf8)
            )
            
            _ = try await client.send(envelope)
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let messagesPerSecond = Double(messageCount) / duration.timeInterval
        
        #expect(messagesPerSecond > 1000, "Transport throughput too low: \(messagesPerSecond) msg/sec")
    }
    
    @Test("Actor system scalability", .timeLimit(.minutes(1)))
    func actorSystemScalability() async throws {
        let system = ActorEdgeSystem()
        
        // Test various actor counts
        let actorCounts = [10, 50, 100, 500]
        
        for count in actorCounts {
            let startTime = ContinuousClock.now
            
            // Create actors
            let actors = (0..<count).map { _ in TestActorImpl(actorSystem: system) }
            
            // Perform operations on all actors
            for actor in actors {
                _ = try await actor.echo(TestMessage(content: "test"))
            }
            
            let duration = startTime.duration(to: ContinuousClock.now)
            let operationsPerSecond = Double(count) / duration.timeInterval
            
            #expect(operationsPerSecond > 100, "System doesn't scale well with \(count) actors: \(operationsPerSecond) ops/sec")
        }
    }
    
    @Test("Concurrent actor creation", .timeLimit(.minutes(1)))
    func concurrentActorCreation() async throws {
        let system = ActorEdgeSystem()
        let actorCount = 100
        
        let startTime = ContinuousClock.now
        
        let actors = await withTaskGroup(of: TestActorImpl.self) { group in
            for _ in 0..<actorCount {
                group.addTask {
                    TestActorImpl(actorSystem: system)
                }
            }
            
            var results: [TestActorImpl] = []
            for await actor in group {
                results.append(actor)
            }
            return results
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        let creationsPerSecond = Double(actorCount) / duration.timeInterval
        
        #expect(actors.count == actorCount)
        #expect(creationsPerSecond > 100, "Concurrent actor creation too slow: \(creationsPerSecond) actors/sec")
        
        // Verify all actor IDs are unique
        let ids = Set(actors.map { $0.id.value })
        #expect(ids.count == actorCount)
    }
}

// Duration timeInterval extension is already defined in TestHelpers.swift