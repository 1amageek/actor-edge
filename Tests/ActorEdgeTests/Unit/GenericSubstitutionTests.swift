import Testing
@testable import ActorEdgeCore
import Distributed

@Suite("Generic Type Substitution Tests", .tags(.core, .regression))
struct GenericSubstitutionTests {
    
    @Test("Message type resolution")
    func messageTypeResolution() async throws {
        // Force type retention
        TestMessage._forceTypeRetention()
        ComplexTestMessage._forceTypeRetention()
        
        let typeName = String(reflecting: TestMessage.self)
        #expect(typeName.contains("TestMessage"))
        
        // Test mangled type name resolution
        if let mangledName = _mangledTypeName(TestMessage.self) {
            let resolvedType = _typeByName(mangledName)
            #expect(resolvedType != nil, "Should resolve TestMessage type from mangled name: \(mangledName)")
        }
    }
    
    @Test("Generic encoding without errors")
    func genericEncodingWithoutErrors() async throws {
        let system = ActorEdgeSystem()
        
        // Create encoder and test generic substitution
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Record generic substitution for TestMessage
        try encoder.recordGenericSubstitution(TestMessage.self)
        
        // Test that encoder can finalize without errors
        try encoder.doneRecording()
        
        // This should not throw the "Generic substitutions do not satisfy" error
        let invocationData = try encoder.finalizeInvocation()
        #expect(invocationData.genericSubstitutions.count == 1)
    }
    
    @Test("Multiple generic substitutions")
    func multipleGenericSubstitutions() async throws {
        let system = ActorEdgeSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test multiple generic substitutions
        try encoder.recordGenericSubstitution(TestMessage.self)
        try encoder.recordGenericSubstitution(ComplexTestMessage.self)
        try encoder.recordGenericSubstitution([TestMessage].self)
        
        try encoder.doneRecording()
        let invocationData = try encoder.finalizeInvocation()
        
        #expect(invocationData.genericSubstitutions.count == 3)
        
        // Verify all types can be resolved
        for typeName in invocationData.genericSubstitutions {
            let resolvedType = _typeByName(typeName)
            #expect(resolvedType != nil, "Should resolve type: \(typeName)")
        }
    }
    
    @Test("Built-in type substitutions")
    func builtinTypeSubstitutions() async throws {
        let system = ActorEdgeSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test built-in types
        try encoder.recordGenericSubstitution(String.self)
        try encoder.recordGenericSubstitution(Int.self)
        try encoder.recordGenericSubstitution([String: Int].self)
        
        try encoder.doneRecording()
        let invocationData = try encoder.finalizeInvocation()
        
        #expect(invocationData.genericSubstitutions.count == 3)
        
        // All built-in types should resolve
        for typeName in invocationData.genericSubstitutions {
            let resolvedType = _typeByName(typeName)
            #expect(resolvedType != nil, "Built-in type should resolve: \(typeName)")
        }
    }
    
    @Test("Encoder-decoder round trip")
    func encoderDecoderRoundTrip() async throws {
        let system = ActorEdgeSystem()
        
        // Create and configure encoder
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordGenericSubstitution(TestMessage.self)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: TestMessage(id: "test-id", content: "test", timestamp: Date())))
        try encoder.doneRecording()
        
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        // Test generic substitutions decoding
        let substitutions = try decoder.decodeGenericSubstitutions()
        #expect(substitutions.count == 1)
        #expect(substitutions[0] == TestMessage.self)
        
        // Test argument decoding
        let decodedMessage: TestMessage = try decoder.decodeNextArgument()
        #expect(decodedMessage.content == "test")
        #expect(decodedMessage.id == "test-id")
    }
    
    @Test("Complex nested type substitutions")
    func complexNestedTypeSubstitutions() async throws {
        let system = ActorEdgeSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test complex nested types
        try encoder.recordGenericSubstitution([String: [TestMessage]].self)
        try encoder.recordGenericSubstitution(Result<TestMessage, TestError>.self)
        try encoder.recordGenericSubstitution(([TestMessage], ComplexTestMessage).self)
        
        try encoder.doneRecording()
        let invocationData = try encoder.finalizeInvocation()
        
        #expect(invocationData.genericSubstitutions.count == 3)
    }
    
    @Test("Actor ID type substitution")
    func actorIDTypeSubstitution() async throws {
        let system = ActorEdgeSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test ActorEdgeID type
        try encoder.recordGenericSubstitution(ActorEdgeID.self)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "actorID", value: ActorEdgeID("test-actor-id")))
        
        try encoder.doneRecording()
        let invocationData = try encoder.finalizeInvocation()
        
        // Create decoder and verify
        var decoder = ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData
        )
        
        let decodedID: ActorEdgeID = try decoder.decodeNextArgument()
        #expect(decodedID.value == "test-actor-id")
    }
    
    @Test("Type resolution with module names")
    func typeResolutionWithModuleNames() async throws {
        // Test type names with module prefixes
        let moduleQualifiedName = "ActorEdgeTests.TestMessage"
        let resolvedType = _typeByName(moduleQualifiedName)
        
        // May or may not resolve depending on how types are registered
        // But should not crash
        _ = resolvedType
    }
    
    @Test("Generic substitution edge cases")
    func genericSubstitutionEdgeCases() async throws {
        let system = ActorEdgeSystem()
        
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Test edge cases
        try encoder.recordGenericSubstitution(Void.self) // Void type
        try encoder.recordGenericSubstitution(Never.self) // Never type
        try encoder.recordGenericSubstitution(Any.self) // Any type
        
        try encoder.doneRecording()
        
        // Should complete without errors
        _ = try encoder.finalizeInvocation()
    }
}