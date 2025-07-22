import Testing
@testable import ActorEdgeCore
import Distributed

@Suite("Invocation Encoder Tests", .tags(.invocation))
struct InvocationEncoderTests {
    
    @Test("Encoder initialization")
    func encoderInitialization() async throws {
        let system = TestHelpers.makeTestActorSystem()
        _ = ActorEdgeInvocationEncoder(system: system)
        
        // Encoder is properly initialized (can't access private system property)
        #expect(Bool(true))
    }
    
    @Test("Record arguments")
    func recordArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let message = TestMessage(content: "test")
        let argument = RemoteCallArgument(label: "message", name: "message", value: message)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 1)
        #expect(!invocation.arguments[0].isEmpty)
    }
    
    @Test("Record return type")
    func recordReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordReturnType(TestMessage.self)
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.isVoid == false)
    }
    
    @Test("Record void return type")
    func recordVoidReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Void type is handled specially - we just don't record a return type
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.isVoid == true)
    }
    
    @Test("Record error type")
    func recordErrorType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordErrorType(ActorEdgeError.self)
        try encoder.doneRecording()
        
        // Should not throw - error type is recorded internally
        _ = try encoder.finalizeInvocation()
    }
    
    @Test("Multiple arguments with different types")
    func multipleArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg1", value: "string_arg"))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg2", value: 42))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg3", value: TestMessage(content: "test")))
        
        try encoder.doneRecording()
        let invocation = try encoder.finalizeInvocation()
        
        #expect(invocation.arguments.count == 3)
        #expect(invocation.argumentManifests.count == 3)
    }
    
    @Test("Recording order compliance")
    func recordingOrderCompliance() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test the correct order as per Apple spec
        // 1. Generic substitutions
        try encoder.recordGenericSubstitution(TestMessage.self)
        
        // 2. Arguments (in declaration order)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg1", value: TestMessage(content: "arg1")))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg2", value: "arg2"))
        
        // 3. Return type
        try encoder.recordReturnType(String.self)
        
        // 4. Error type
        try encoder.recordErrorType(TestError.self)
        
        // 5. Done recording
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.genericSubstitutions.count == 1)
        #expect(invocation.arguments.count == 2)
        #expect(!invocation.isVoid)
    }
    
    @Test("Complex argument types")
    func complexArgumentTypes() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test with complex nested types
        let complexMessage = ComplexTestMessage(
            messages: [
                TestMessage(content: "nested1"),
                TestMessage(content: "nested2")
            ],
            metadata: ["key1": "value1", "key2": "value2"],
            optional: "optional value"
        )
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: complexMessage))
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 1)
        #expect(invocation.arguments[0].count > 100) // Complex message should produce larger payload
    }
    
    @Test("Array and dictionary arguments")
    func arrayAndDictionaryArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let array = [1, 2, 3, 4, 5]
        let dictionary = ["key1": "value1", "key2": "value2"]
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "array", value: array))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "dict", value: dictionary))
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 2)
    }
    
    @Test("Empty collections")
    func emptyCollections() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let emptyArray: [String] = []
        let emptyDict: [String: Int] = [:]
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "emptyArray", value: emptyArray))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "emptyDict", value: emptyDict))
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 2)
    }
    
    @Test("Optional arguments")
    func optionalArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let someValue: String? = "present"
        let noneValue: String? = nil
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "someValue", value: someValue))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "noneValue", value: noneValue))
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 2)
    }
    
    @Test("Distributed actor ID arguments")
    func distributedActorIDArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let actorID = ActorEdgeID("test-actor-123")
        
        try encoder.recordGenericSubstitution(ActorEdgeID.self)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "actorID", value: actorID))
        try encoder.doneRecording()
        
        let invocation = try encoder.finalizeInvocation()
        #expect(invocation.arguments.count == 1)
        #expect(invocation.genericSubstitutions.count == 1)
    }
    
    @Test("Encoder finalization without doneRecording throws")
    func encoderFinalizationWithoutDoneRecording() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "test", value: "test"))
        
        // Should throw because doneRecording wasn't called
        #expect(throws: ActorEdgeError.self) {
            _ = try encoder.finalizeInvocation()
        }
    }
    
    @Test("Multiple generic substitutions with complex types")
    func multipleGenericSubstitutionsComplex() async throws {
        let system = TestHelpers.makeTestActorSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Record various generic types
        try encoder.recordGenericSubstitution(TestMessage.self)
        try encoder.recordGenericSubstitution([TestMessage].self)
        try encoder.recordGenericSubstitution([String: TestMessage].self)
        try encoder.recordGenericSubstitution(Result<TestMessage, TestError>.self)
        
        try encoder.doneRecording()
        let invocation = try encoder.finalizeInvocation()
        
        #expect(invocation.genericSubstitutions.count == 4)
    }
}