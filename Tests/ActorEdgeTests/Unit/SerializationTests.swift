import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for ActorEdge serialization functionality
@Suite("Serialization Tests")
struct SerializationTests {
    
    // MARK: - Test Helpers
    
    /// Create a test actor system
    func createTestSystem() -> ActorEdgeSystem {
        return ActorEdgeSystem()
    }
    
    // MARK: - Test Types
    
    struct SimpleMessage: Codable, Sendable, Equatable {
        let id: Int
        let message: String
    }
    
    struct ComplexMessage: Codable, Sendable, Equatable {
        let id: UUID
        let timestamp: Date
        let data: [String: Int]
        let optional: String?
    }
    
    enum TestError: Error, Codable {
        case simpleError
        case errorWithMessage(String)
    }
    
    // MARK: - InvocationEncoder Tests
    
    @Test("Encode simple argument")
    func testEncodeSimpleArgument() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let message = SimpleMessage(id: 42, message: "Hello")
        let argument = RemoteCallArgument(label: nil, name: "arg", value: message)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.method")
        #expect(invocationMessage.arguments.count == 1)
        
        // Serialize the message
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        #expect(data.count > 0)
        
        // Verify the data can be decoded
        let decodedInvocationMessage = try system.serialization.deserialize(InvocationMessage.self, from: SerializationBuffer.data(data))
        #expect(decodedInvocationMessage.arguments.count == 1)
        
        // Decode the argument back
        let decodedMessage = try system.serialization.deserialize(SimpleMessage.self, from: SerializationBuffer.data(decodedInvocationMessage.arguments[0]))
        #expect(decodedMessage == message)
    }
    
    @Test("Encode multiple arguments")
    func testEncodeMultipleArguments() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let arg1 = RemoteCallArgument(label: nil, name: "arg1", value: "Hello")
        let arg2 = RemoteCallArgument(label: nil, name: "arg2", value: 42)
        let arg3 = RemoteCallArgument(label: nil, name: "arg3", value: true)
        
        try encoder.recordArgument(arg1)
        try encoder.recordArgument(arg2)
        try encoder.recordArgument(arg3)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.multipleArgs")
        
        #expect(invocationMessage.arguments.count == 3)
        
        // Decode arguments back
        let decodedArg1 = try system.serialization.deserialize(String.self, from: SerializationBuffer.data(invocationMessage.arguments[0]))
        let decodedArg2 = try system.serialization.deserialize(Int.self, from: SerializationBuffer.data(invocationMessage.arguments[1]))
        let decodedArg3 = try system.serialization.deserialize(Bool.self, from: SerializationBuffer.data(invocationMessage.arguments[2]))
        
        #expect(decodedArg1 == "Hello")
        #expect(decodedArg2 == 42)
        #expect(decodedArg3 == true)
    }
    
    @Test("Encode complex types")
    func testEncodeComplexTypes() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let date = Date()
        let message = ComplexMessage(
            id: UUID(),
            timestamp: date,
            data: ["one": 1, "two": 2, "three": 3],
            optional: "Optional value"
        )
        
        let argument = RemoteCallArgument(label: nil, name: "arg", value: message)
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.complexTypes")
        
        // Decode and verify
        let decodedMessage = try system.serialization.deserialize(ComplexMessage.self, from: SerializationBuffer.data(invocationMessage.arguments[0]))
        #expect(decodedMessage.id == message.id)
        // Date comparison with tolerance due to ISO8601 encoding
        let timeDifference = abs(decodedMessage.timestamp.timeIntervalSince(message.timestamp))
        #expect(timeDifference < 1.0)
        #expect(decodedMessage.data == message.data)
        #expect(decodedMessage.optional == message.optional)
    }
    
    @Test("Encode generic substitutions")
    func testEncodeGenericSubstitutions() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordGenericSubstitution(String.self)
        try encoder.recordGenericSubstitution(Int.self)
        try encoder.recordGenericSubstitution([String: Int].self)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.genericSubstitutions")
        
        #expect(invocationMessage.genericSubstitutions.count == 3)
        #expect(invocationMessage.genericSubstitutions[0] == "Swift.String")
        #expect(invocationMessage.genericSubstitutions[1] == "Swift.Int")
        #expect(invocationMessage.genericSubstitutions[2].contains("Dictionary"))
    }
    
    @Test("Encode return and error types")
    func testEncodeReturnAndErrorTypes() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordReturnType(String.self)
        try encoder.recordErrorType(TestError.self)
        try encoder.doneRecording()
        
        // Return and error types are recorded but not included in InvocationMessage
        // They are stored internally for protocol conformance
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.returnAndError")
        
        // Just verify the message was created successfully
        #expect(invocationMessage.targetIdentifier == "test.returnAndError")
    }
    
    // MARK: - InvocationDecoder Tests
    
    @Test("Decode simple argument")
    func testDecodeSimpleArgument() async throws {
        // First encode
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        let message = SimpleMessage(id: 123, message: "Test")
        let argument = RemoteCallArgument(label: nil, name: "arg", value: message)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.decode")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        // Then decode
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decodedMessage: SimpleMessage = try decoder.decodeNextArgument()
        
        #expect(decodedMessage == message)
    }
    
    @Test("Decode multiple arguments")
    func testDecodeMultipleArguments() async throws {
        // Encode multiple arguments
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "First"))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: 123))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: 45.67))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: false))
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.multiDecode")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        // Decode them back
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        
        let arg1: String = try decoder.decodeNextArgument()
        let arg2: Int = try decoder.decodeNextArgument()
        let arg3: Double = try decoder.decodeNextArgument()
        let arg4: Bool = try decoder.decodeNextArgument()
        
        #expect(arg1 == "First")
        #expect(arg2 == 123)
        #expect(arg3 == 45.67)
        #expect(arg4 == false)
    }
    
    @Test("Decode with missing argument error")
    func testDecodeMissingArgument() async throws {
        // Encode one argument
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "Only one"))
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.missingArg")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        // Try to decode two arguments
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        
        let _: String = try decoder.decodeNextArgument()
        
        // This should throw
        do {
            let _: String = try decoder.decodeNextArgument()
            #expect(Bool(false), "Should have thrown missingArgument error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    @Test("Decode with system initializer")
    func testDecodeWithSystemInitializer() async throws {
        // Create encoded data
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "Test with system"))
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.withSystem")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        // Decode with system
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decoded: String = try decoder.decodeNextArgument()
        
        #expect(decoded == "Test with system")
    }
    
    @Test("Decode with invalid data")
    func testDecodeWithInvalidData() async throws {
        let system = ActorEdgeSystem()
        let invalidData = Data("invalid json".utf8)
        
        // Initializing with invalid data should throw
        do {
            var decoder = try ActorEdgeInvocationDecoder(system: system, payload: invalidData)
            let _: String = try decoder.decodeNextArgument()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    // MARK: - Date Encoding/Decoding Tests
    
    @Test("Date encoding and decoding")
    func testDateEncodingDecoding() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let now = Date()
        let argument = RemoteCallArgument(label: nil, name: "arg", value: now)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.date")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decodedDate: Date = try decoder.decodeNextArgument()
        
        // Dates should be equal within second precision (due to ISO8601 encoding)
        let difference = abs(decodedDate.timeIntervalSince(now))
        #expect(difference < 1.0)
    }
    
    // MARK: - Array and Dictionary Tests
    
    @Test("Array encoding and decoding")
    func testArrayEncodingDecoding() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let array = [1, 2, 3, 4, 5]
        let argument = RemoteCallArgument(label: nil, name: "arg", value: array)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.array")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decodedArray: [Int] = try decoder.decodeNextArgument()
        
        #expect(decodedArray == array)
    }
    
    @Test("Dictionary encoding and decoding")
    func testDictionaryEncodingDecoding() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        let dict = ["apple": 1, "banana": 2, "cherry": 3]
        let argument = RemoteCallArgument(label: nil, name: "arg", value: dict)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.dictionary")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decodedDict: [String: Int] = try decoder.decodeNextArgument()
        
        #expect(decodedDict == dict)
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance of large payload encoding")
    func testLargePayloadPerformance() async throws {
        let system = createTestSystem()
        var encoder = ActorEdgeInvocationEncoder(system: system)
        
        // Create a large array
        let largeArray = Array(0..<1000).map { SimpleMessage(id: $0, message: "Message \($0)") }
        let argument = RemoteCallArgument(label: nil, name: "arg", value: largeArray)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        let invocationMessage = try encoder.createInvocationMessage(targetIdentifier: "test.performance")
        let messageBuffer = try system.serialization.serialize(invocationMessage)
        let data = messageBuffer.readData()
        
        let encodingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Decoding
        let decodeStartTime = CFAbsoluteTimeGetCurrent()
        var decoder = try ActorEdgeInvocationDecoder(system: system, payload: data)
        let decoded: [SimpleMessage] = try decoder.decodeNextArgument()
        let decodingTime = CFAbsoluteTimeGetCurrent() - decodeStartTime
        
        #expect(decoded.count == 1000)
        #expect(encodingTime < 0.1, "Encoding should complete within 100ms")
        #expect(decodingTime < 0.1, "Decoding should complete within 100ms")
    }
}

// MARK: - Helper Types