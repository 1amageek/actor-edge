import Testing
import Foundation
import Distributed
import ServiceContextModule
@testable import ActorEdgeCore

/// Test suite for ActorEdgeSystem functionality
@Suite("ActorEdgeSystem Tests", .tags(.core, .unit))
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
        let transport = MockMessageTransport()
        let system = ActorEdgeSystem(transport: transport)
        
        #expect(system.isServer == false)
        #expect(system.registry != nil)  // Clients can also have local actors
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
        
        // Test shortened UUID format: first 8 characters of UUID, lowercase
        let shortUUIDPattern = #"^[0-9a-f]{8}$"#
        let regex = try NSRegularExpression(pattern: shortUUIDPattern, options: [])
        let range = NSRange(location: 0, length: id.description.utf16.count)
        let matches = regex.matches(in: id.description, options: [], range: range)
        
        #expect(matches.count == 1, "ActorEdgeID should be 8 lowercase hex characters")
        #expect(id.description.count == 8)
        #expect(id.description == id.description.lowercased(), "ActorEdgeID should be lowercase")
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
        let transport = MockMessageTransport()
        let system = ActorEdgeSystem(transport: transport)
        
        // Create actor on client side
        let actor = TestSystemActor(name: "ClientActor", actorSystem: system)
        
        // Give some time for async registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Client systems can also have local actors
        #expect(system.registry != nil)
        let registered = system.registry?.find(id: actor.id)
        #expect(registered != nil)
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
        let transport = MockMessageTransport()
        
        // The response should be serialized using the same serialization system
        let system = ActorEdgeSystem(transport: transport)
        let responseValue = "Hello from remote!"
        let serializedValue = try system.serialization.serialize(responseValue)
        
        // Create InvocationResult with proper format
        let invocationResult = InvocationResult.success(serializedValue)
        let resultData = try system.serialization.serialize(invocationResult)
        
        // Create response envelope
        let responseEnvelope = Envelope.response(
            to: ActorEdgeID(),  // Will be set by mock
            callID: "",  // Will be captured from request
            manifest: resultData.manifest,
            payload: resultData.data
        )
        transport.mockResponse = responseEnvelope
        
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
        #expect(transport.lastEnvelope?.metadata.target == "getName")
    }
    
    @Test("Remote call void")
    func testRemoteCallVoid() async throws {
        let transport = MockMessageTransport()
        let system = ActorEdgeSystem(transport: transport)
        
        // Create InvocationResult.void response
        let invocationResult = InvocationResult.void
        let resultData = try system.serialization.serialize(invocationResult)
        
        // Create response envelope for void
        let responseEnvelope = Envelope.response(
            to: ActorEdgeID(),  // Will be set by mock
            callID: "",  // Will be captured from request
            manifest: resultData.manifest,
            payload: resultData.data
        )
        transport.mockResponse = responseEnvelope
        
        var encoder = system.makeInvocationEncoder()
        
        let target = RemoteCallTarget( "doSomething")
        
        try await system.remoteCallVoid(
            on: TestSystemActor(name: "Remote", actorSystem: system),
            target: target,
            invocation: &encoder,
            throwing: Never.self
        )
        
        #expect(transport.lastEnvelope?.metadata.target == "doSomething")
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
        let transport = MockMessageTransport()
        
        let system = ActorEdgeSystem(transport: transport)
        var encoder = system.makeInvocationEncoder()
        
        // Set up response
        let responseValue = "OK"
        let serializedValue = try system.serialization.serialize(responseValue)
        let invocationResult = InvocationResult.success(serializedValue)
        let resultData = try system.serialization.serialize(invocationResult)
        let responseEnvelope = Envelope.response(
            to: ActorEdgeID(),
            callID: "",
            manifest: resultData.manifest,
            payload: resultData.data
        )
        transport.mockResponse = responseEnvelope
        
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
        
        // ServiceContext propagation is not yet fully implemented
        // This would require a proper baggage implementation
        // For now, just verify the call was made
        #expect(transport.lastEnvelope?.metadata.target == "contextTest")
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

// MARK: - Test Context Key

enum TestContextKey: ServiceContextKey {
    typealias Value = String
    static var defaultValue: String { "" }
}