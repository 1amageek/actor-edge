import Testing
@testable import ActorEdgeCore
import Distributed
import Foundation

@Suite("Invocation Decoder Tests", .tags(.invocation))
struct InvocationDecoderTests {
    
    @Test("Decoder initialization with invocation data")
    func decoderInitialization() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create invocation data
        let invocationData = InvocationData(
            genericSubstitutions: [String(reflecting: TestMessage.self)],
            arguments: [Data("test".utf8)],
            argumentManifests: [SerializationManifest(serializerID: "json")],
            isVoid: false
        )
        
        let decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        #expect(decoder.system === system)
    }
    
    @Test("Decode generic substitutions")
    func decodeGenericSubstitutions() async throws {
        // Force type retention
        TestMessage._forceTypeRetention()
        ComplexTestMessage._forceTypeRetention()
        
        let system = TestHelpers.makeTestActorSystem()
        
        // Create encoder and record substitutions
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordGenericSubstitution(TestMessage.self)
        try encoder.recordGenericSubstitution(ComplexTestMessage.self)
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // Decode generic substitutions
        let substitutions = try decoder.decodeGenericSubstitutions()
        #expect(substitutions.count == 2)
        #expect(substitutions[0] == TestMessage.self)
        #expect(substitutions[1] == ComplexTestMessage.self)
    }
    
    @Test("Decode next argument")
    func decodeNextArgument() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create encoder with argument
        var encoder = ActorEdgeInvocationEncoder(system: system)
        let testMessage = TestMessage(id: "test-123", content: "Hello decoder")
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: testMessage))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // Decode argument
        let decodedMessage: TestMessage = try decoder.decodeNextArgument()
        #expect(decodedMessage.id == testMessage.id)
        #expect(decodedMessage.content == testMessage.content)
    }
    
    @Test("Decode multiple arguments in order")
    func decodeMultipleArguments() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create encoder with multiple arguments
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg1", value: "first"))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg2", value: 42))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg3", value: true))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // Decode arguments in order
        let arg1: String = try decoder.decodeNextArgument()
        let arg2: Int = try decoder.decodeNextArgument()
        let arg3: Bool = try decoder.decodeNextArgument()
        
        #expect(arg1 == "first")
        #expect(arg2 == 42)
        #expect(arg3 == true)
    }
    
    @Test("Decode complex nested types")
    func decodeComplexTypes() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create complex message
        let complexMessage = ComplexTestMessage(
            messages: [
                TestMessage(content: "msg1"),
                TestMessage(content: "msg2")
            ],
            metadata: ["key": "value"],
            optional: "optional",
            numbers: [1, 2, 3],
            nested: ComplexTestMessage.NestedData(
                flag: true,
                values: ["pi": 3.14159, "e": 2.71828]
            )
        )
        
        // Encode
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: complexMessage))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Decode
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let decoded: ComplexTestMessage = try decoder.decodeNextArgument()
        
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[0].content == "msg1")
        #expect(decoded.metadata["key"] == "value")
        #expect(decoded.optional == "optional")
        #expect(decoded.numbers == [1, 2, 3])
        #expect(decoded.nested.flag == true)
        #expect(decoded.nested.values["pi"] == 3.14159)
    }
    
    @Test("Decode actor ID argument")
    func decodeActorID() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let actorID = ActorEdgeID("actor-456")
        
        // Encode
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "actorID", value: actorID))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Decode
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let decodedID: ActorEdgeID = try decoder.decodeNextArgument()
        #expect(decodedID.value == actorID.value)
    }
    
    @Test("Decode empty collections")
    func decodeEmptyCollections() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let emptyArray: [String] = []
        let emptyDict: [Int: String] = [:]
        
        // Encode
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "emptyArray", value: emptyArray))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "emptyDict", value: emptyDict))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Decode
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let decodedArray: [String] = try decoder.decodeNextArgument()
        let decodedDict: [Int: String] = try decoder.decodeNextArgument()
        
        #expect(decodedArray.isEmpty)
        #expect(decodedDict.isEmpty)
    }
    
    @Test("Decode optional values")
    func decodeOptionalValues() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let someValue: String? = "present"
        let noneValue: String? = nil
        
        // Encode
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "someValue", value: someValue))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "noneValue", value: noneValue))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Decode
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let decodedSome: String? = try decoder.decodeNextArgument()
        let decodedNone: String? = try decoder.decodeNextArgument()
        
        #expect(decodedSome == "present")
        #expect(decodedNone == nil)
    }
    
    @Test("Decode return type")
    func decodeReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Test that return type is properly handled
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordReturnType(TestMessage.self)
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // Return type decoding is handled internally
        let returnType = try decoder.decodeReturnType()
        #expect(returnType == TestMessage.self)
    }
    
    @Test("Decode void return type")
    func decodeVoidReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordReturnType(Void.self)
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        #expect(invocationData.isVoid == true)
        
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let returnType = try decoder.decodeReturnType()
        #expect(returnType == Void.self)
    }
    
    @Test("Decode error type")
    func decodeErrorType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordErrorType(TestError.self)
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let errorType = try decoder.decodeErrorType()
        #expect(errorType == TestError.self)
    }
    
    @Test("Decoder argument index bounds")
    func decoderArgumentIndexBounds() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create encoder with one argument
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "only one"))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // First decode should succeed
        let _: String = try decoder.decodeNextArgument()
        
        // Second decode should throw (no more arguments)
        await #expect(throws: ActorEdgeError.self) {
            let _: String = try decoder.decodeNextArgument()
        }
    }
    
    @Test("UserInfo actor system key")
    func userInfoActorSystemKey() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create a distributed actor for testing
        let testActor = TestActorImpl(actorSystem: system)
        
        // Encode an actor ID as argument
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "actorID", value: testActor.id))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder - it should set userInfo[.actorSystemKey]
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // The decoder should be able to resolve actor IDs using the system
        let decodedID: ActorEdgeID = try decoder.decodeNextArgument()
        #expect(decodedID.value == testActor.id.value)
    }
}