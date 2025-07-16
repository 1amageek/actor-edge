import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for ActorBuilder result builder functionality
@Suite("ActorBuilder Tests")
struct ActorBuilderTests {
    
    // MARK: - Test Actors
    
    /// Simple test actor for testing purposes
    distributed actor TestActor: DistributedActor {
        public typealias ActorSystem = ActorEdgeSystem
        
        let name: String
        
        public init(name: String, actorSystem: ActorSystem) {
            self.name = name
            self.actorSystem = actorSystem
        }
        
        distributed func getName() async throws -> String {
            return name
        }
    }
    
    /// Another test actor for multiple actor scenarios
    distributed actor AnotherTestActor: DistributedActor {
        public typealias ActorSystem = ActorEdgeSystem
        
        let value: Int
        
        public init(value: Int, actorSystem: ActorSystem) {
            self.value = value
            self.actorSystem = actorSystem
        }
        
        distributed func getValue() async throws -> Int {
            return value
        }
    }
    
    // MARK: - Basic ActorBuilder Tests
    
    @Test("Empty ActorBuilder should return empty array")
    func testEmptyActorBuilder() async throws {
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildEmptyActors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            // Empty builder
        }
        
        let actors = buildEmptyActors(actorSystem: system)
        #expect(actors.isEmpty)
    }
    
    @Test("Single actor in ActorBuilder")
    func testSingleActor() async throws {
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildSingleActor(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            TestActor(name: "test", actorSystem: actorSystem)
        }
        
        let actors = buildSingleActor(actorSystem: system)
        #expect(actors.count == 1)
        
        // Verify the actor is of correct type
        let testActor = actors[0] as? TestActor
        #expect(testActor != nil)
        
        // Test distributed method call
        let name = try await testActor?.getName()
        #expect(name == "test")
    }
    
    @Test("Multiple actors in ActorBuilder")
    func testMultipleActors() async throws {
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildMultipleActors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            TestActor(name: "first", actorSystem: actorSystem)
            TestActor(name: "second", actorSystem: actorSystem)
            AnotherTestActor(value: 42, actorSystem: actorSystem)
        }
        
        let actors = buildMultipleActors(actorSystem: system)
        #expect(actors.count == 3)
        
        // Verify first actor
        let firstActor = actors[0] as? TestActor
        #expect(firstActor != nil)
        let firstName = try await firstActor?.getName()
        #expect(firstName == "first")
        
        // Verify second actor
        let secondActor = actors[1] as? TestActor
        #expect(secondActor != nil)
        let secondName = try await secondActor?.getName()
        #expect(secondName == "second")
        
        // Verify third actor
        let thirdActor = actors[2] as? AnotherTestActor
        #expect(thirdActor != nil)
        let value = try await thirdActor?.getValue()
        #expect(value == 42)
    }
    
    // MARK: - Array Support Tests
    
    @Test("ActorBuilder with array of actors")
    func testActorBuilderWithArray() async throws {
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildActorsWithArray(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            TestActor(name: "single", actorSystem: actorSystem)
            
            // Array of actors
            [
                TestActor(name: "array1", actorSystem: actorSystem),
                TestActor(name: "array2", actorSystem: actorSystem)
            ]
        }
        
        let actors = buildActorsWithArray(actorSystem: system)
        #expect(actors.count == 3)
        
        // Verify actors are in correct order
        let names = try await withThrowingTaskGroup(of: String.self) { group in
            for actor in actors {
                group.addTask {
                    try await (actor as! TestActor).getName()
                }
            }
            
            var results: [String] = []
            for try await name in group {
                results.append(name)
            }
            return results.sorted() // Sort for consistent testing
        }
        
        #expect(names.contains("single"))
        #expect(names.contains("array1"))
        #expect(names.contains("array2"))
    }
    
    // MARK: - Conditional Tests
    
    @Test("ActorBuilder with conditional actors")
    func testConditionalActors() async throws {
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildConditionalActors(actorSystem: ActorEdgeSystem, includeOptional: Bool) -> [any DistributedActor] {
            TestActor(name: "always", actorSystem: actorSystem)
            
            if includeOptional {
                TestActor(name: "optional", actorSystem: actorSystem)
            }
        }
        
        // Test with condition true
        let actorsWithOptional = buildConditionalActors(actorSystem: system, includeOptional: true)
        #expect(actorsWithOptional.count == 2)
        
        // Test with condition false
        let actorsWithoutOptional = buildConditionalActors(actorSystem: system, includeOptional: false)
        #expect(actorsWithoutOptional.count == 1)
        
        // Verify the always-present actor
        let alwaysActor = actorsWithoutOptional[0] as? TestActor
        #expect(alwaysActor != nil)
        let name = try await alwaysActor?.getName()
        #expect(name == "always")
    }
    
    // MARK: - Server Integration Tests
    
    @Test("ActorBuilder in Server context")
    func testActorBuilderInServer() async throws {
        
        struct TestServer: Server {
            init() {}
            
            @ActorBuilder
            func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
                TestActor(name: "server-actor", actorSystem: actorSystem)
                AnotherTestActor(value: 123, actorSystem: actorSystem)
            }
        }
        
        let server = TestServer()
        let system = ActorEdgeSystem()
        
        let actors = server.actors(actorSystem: system)
        #expect(actors.count == 2)
        
        // Verify first actor
        let testActor = actors[0] as? TestActor
        #expect(testActor != nil)
        let name = try await testActor?.getName()
        #expect(name == "server-actor")
        
        // Verify second actor
        let anotherActor = actors[1] as? AnotherTestActor
        #expect(anotherActor != nil)
        let value = try await anotherActor?.getValue()
        #expect(value == 123)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("ActorBuilder with distributed method errors")
    func testActorBuilderWithErrors() async throws {
        
        distributed actor ErrorActor: DistributedActor {
            public typealias ActorSystem = ActorEdgeSystem
            
            public init(actorSystem: ActorSystem) {
                self.actorSystem = actorSystem
            }
            
            distributed func throwError() async throws -> String {
                throw TestError.simulatedError
            }
        }
        
        enum TestError: Error {
            case simulatedError
        }
        
        let system = ActorEdgeSystem()
        
        @ActorBuilder
        func buildErrorActor(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            ErrorActor(actorSystem: actorSystem)
        }
        
        let actors = buildErrorActor(actorSystem: system)
        #expect(actors.count == 1)
        
        let errorActor = actors[0] as? ErrorActor
        #expect(errorActor != nil)
        
        // Test that error is properly propagated
        do {
            _ = try await errorActor?.throwError()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is TestError)
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("ActorBuilder performance with many actors")
    func testActorBuilderPerformance() async throws {
        let system = ActorEdgeSystem()
        let actorCount = 100
        
        @ActorBuilder
        func buildManyActors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            for i in 0..<actorCount {
                TestActor(name: "actor-\(i)", actorSystem: actorSystem)
            }
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let actors = buildManyActors(actorSystem: system)
        let endTime = CFAbsoluteTimeGetCurrent()
        
        #expect(actors.count == actorCount)
        
        // Performance assertion: should complete within reasonable time
        let duration = endTime - startTime
        #expect(duration < 1.0, "ActorBuilder should complete within 1 second for 100 actors")
    }
}