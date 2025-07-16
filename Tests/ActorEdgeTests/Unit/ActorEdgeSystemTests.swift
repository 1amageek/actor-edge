import Testing
import Foundation
import Distributed
import ServiceContextModule
@testable import ActorEdgeCore

/// Test suite for ActorEdgeSystem functionality
@Suite("ActorEdgeSystem Tests")
struct ActorEdgeSystemTests {
    
    // MARK: - Test Actors
    
    /// Simple test actor for testing purposes
    distributed actor TestSystemActor: DistributedActor {
        public typealias ActorSystem = ActorEdgeSystem
        
        let name: String
        
        public init(name: String, actorSystem: ActorSystem) {
            self.name = name
            self.actorSystem = actorSystem
        }
        
        distributed func getName() async throws -> String {
            return name
        }
        
        distributed func greet(_ person: String) async throws -> String {
            return "Hello, \(person)! I'm \(name)"
        }
    }
    
    // MARK: - System Initialization Tests
    
    @Test("Server-side system initialization")
    func testServerSystemInitialization() async throws {
        let system = ActorEdgeSystem()
        
        #expect(system.isServer == true)
        #expect(system.registry != nil)
    }
    
    @Test("Client-side system initialization")
    func testClientSystemInitialization() async throws {
        let transport = MockActorTransport()
        let system = ActorEdgeSystem(transport: transport)
        
        #expect(system.isServer == false)
        #expect(system.registry == nil)
    }
    
    // MARK: - Actor ID Assignment Tests
    
    @Test("Assign ID to new actor")
    func testAssignID() async throws {
        let system = ActorEdgeSystem()
        
        let id1 = system.assignID(TestSystemActor.self)
        let id2 = system.assignID(TestSystemActor.self)
        
        #expect(id1 != id2) // IDs should be unique
        #expect(!id1.description.isEmpty)
        #expect(!id2.description.isEmpty)
    }
    
    @Test("ActorEdgeID format validation")
    func testActorIDFormat() async throws {
        let system = ActorEdgeSystem()
        let id = system.assignID(TestSystemActor.self)
        
        // Test base64url format (no padding, URL-safe characters)
        #expect(!id.description.contains("="))
        #expect(!id.description.contains("/"))
        #expect(!id.description.contains("+"))
        #expect(id.description.count == 22) // 128 bits = 16 bytes = 22 base64 chars (padding removed)
    }
    
    // MARK: - Actor Lifecycle Tests
    
    @Test("Actor ready lifecycle on server")
    func testActorReadyServer() async throws {
        let system = ActorEdgeSystem()
        let actor = TestSystemActor(name: "TestActor", actorSystem: system)
        
        // Actor should be registered in the registry
        let registry = system.registry!
        
        // Give some time for async registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        let registered = await registry.find(id: actor.id)
        #expect(registered != nil)
    }
    
    @Test("Actor ready lifecycle on client")
    func testActorReadyClient() async throws {
        let transport = MockActorTransport()
        let system = ActorEdgeSystem(transport: transport)
        
        // Create actor on client side
        let _ = TestSystemActor(name: "ClientActor", actorSystem: system)
        
        // Should not crash, but won't register (no registry on client)
        #expect(system.registry == nil)
    }
    
    @Test("Actor resign ID lifecycle")
    func testResignID() async throws {
        let system = ActorEdgeSystem()
        let actor = TestSystemActor(name: "ResignTest", actorSystem: system)
        let id = actor.id
        
        // Give some time for async registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Verify actor is registered
        var registered = await system.registry?.find(id: id)
        #expect(registered != nil)
        
        // Resign the ID
        system.resignID(id)
        
        // Give some time for async unregistration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Verify actor is unregistered
        registered = await system.registry?.find(id: id)
        #expect(registered == nil)
    }
    
    // MARK: - Remote Call Tests
    
    @Test("Remote call with result")
    func testRemoteCallWithResult() async throws {
        let transport = MockActorTransport()
        transport.mockResponse = try JSONEncoder().encode("Hello from remote!")
        
        let system = ActorEdgeSystem(transport: transport)
        var encoder = system.makeInvocationEncoder()
        try encoder.recordGenericSubstitution(String.self)
        
        let target = RemoteCallTarget( "getName")
        
        let result: String = try await system.remoteCall(
            on: TestSystemActor(name: "Remote", actorSystem: system),
            target: target,
            invocation: &encoder,
            throwing: Never.self,
            returning: String.self
        )
        
        #expect(result == "Hello from remote!")
        #expect(transport.lastMethodCalled == "getName")
    }
    
    @Test("Remote call void")
    func testRemoteCallVoid() async throws {
        let transport = MockActorTransport()
        let system = ActorEdgeSystem(transport: transport)
        var encoder = system.makeInvocationEncoder()
        
        let target = RemoteCallTarget( "doSomething")
        
        try await system.remoteCallVoid(
            on: TestSystemActor(name: "Remote", actorSystem: system),
            target: target,
            invocation: &encoder,
            throwing: Never.self
        )
        
        #expect(transport.lastMethodCalled == "doSomething")
        #expect(transport.voidCallCount == 1)
    }
    
    @Test("Remote call with error - no transport")
    func testRemoteCallNoTransport() async throws {
        let system = ActorEdgeSystem() // Server system, no transport
        var encoder = system.makeInvocationEncoder()
        
        let target = RemoteCallTarget( "getName")
        
        do {
            let _: String = try await system.remoteCall(
                on: TestSystemActor(name: "Test", actorSystem: system),
                target: target,
                invocation: &encoder,
                throwing: Never.self,
                returning: String.self
            )
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    // MARK: - Service Context Tests
    
    @Test("Service context propagation in remote calls")
    func testServiceContextPropagation() async throws {
        let transport = MockActorTransport()
        transport.mockResponse = try JSONEncoder().encode("OK")
        
        let system = ActorEdgeSystem(transport: transport)
        var encoder = system.makeInvocationEncoder()
        
        // Set up service context
        var context = ServiceContext.topLevel
        context[TestContextKey.self] = "test-value"
        
        let target = RemoteCallTarget( "contextTest")
        
        try await ServiceContext.withValue(context) {
            let _: String = try await system.remoteCall(
                on: TestSystemActor(name: "Context", actorSystem: system),
                target: target,
                invocation: &encoder,
                throwing: Never.self,
                returning: String.self
            )
        }
        
        #expect(transport.lastContext?[TestContextKey.self] == "test-value")
    }
    
    // MARK: - Multiple System Instance Tests
    
    @Test("Multiple systems can coexist")
    func testMultipleSystems() async throws {
        let system1 = ActorEdgeSystem()
        let system2 = ActorEdgeSystem()
        
        let actor1 = TestSystemActor(name: "Actor1", actorSystem: system1)
        let actor2 = TestSystemActor(name: "Actor2", actorSystem: system2)
        
        #expect(actor1.id != actor2.id)
        
        // Give some time for async registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Each system should have its own registry
        let registered1 = await system1.registry?.find(id: actor1.id)
        let registered2 = await system2.registry?.find(id: actor2.id)
        
        #expect(registered1 != nil)
        #expect(registered2 != nil)
        
        // Cross-check: actor1 should not be in system2's registry
        let crossCheck1 = await system2.registry?.find(id: actor1.id)
        let crossCheck2 = await system1.registry?.find(id: actor2.id)
        
        #expect(crossCheck1 == nil)
        #expect(crossCheck2 == nil)
    }
}

// MARK: - Mock Transport

/// Mock transport for testing
final class MockActorTransport: ActorTransport, @unchecked Sendable {
    var mockResponse: Data = Data()
    var lastMethodCalled: String?
    var lastActorID: ActorEdgeID?
    var lastArguments: Data?
    var lastContext: ServiceContext?
    var voidCallCount = 0
    var shouldThrowError = false
    
    func remoteCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> Data {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock error")
        }
        
        lastMethodCalled = method
        lastActorID = actorID
        lastArguments = arguments
        lastContext = context
        
        return mockResponse
    }
    
    func remoteCallVoid(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock error")
        }
        
        lastMethodCalled = method
        lastActorID = actorID
        lastArguments = arguments
        lastContext = context
        voidCallCount += 1
    }
    
    func streamCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> AsyncThrowingStream<Data, any Error> {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock error")
        }
        
        lastMethodCalled = method
        lastActorID = actorID
        lastArguments = arguments
        lastContext = context
        
        return AsyncThrowingStream<Data, any Error> { continuation in
            continuation.yield(mockResponse)
            continuation.finish()
        }
    }
}

// MARK: - Test Context Key

enum TestContextKey: ServiceContextKey {
    typealias Value = String
    static var defaultValue: String { "" }
}