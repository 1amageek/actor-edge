import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for ActorEdge serialization functionality
@Suite("Serialization Tests")
struct SerializationTests {
    
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
        var encoder = ActorEdgeInvocationEncoder()
        
        let message = SimpleMessage(id: 42, message: "Hello")
        let argument = RemoteCallArgument(label: nil, name: "arg", value: message)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        #expect(data.count > 0)
        
        // Verify the data can be decoded
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        
        #expect(envelope.arguments.count == 1)
        
        // Decode the argument back
        let decodedMessage = try decoder.decode(SimpleMessage.self, from: envelope.arguments[0])
        #expect(decodedMessage == message)
    }
    
    @Test("Encode multiple arguments")
    func testEncodeMultipleArguments() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        let arg1 = RemoteCallArgument(label: nil, name: "arg1", value: "Hello")
        let arg2 = RemoteCallArgument(label: nil, name: "arg2", value: 42)
        let arg3 = RemoteCallArgument(label: nil, name: "arg3", value: true)
        
        try encoder.recordArgument(arg1)
        try encoder.recordArgument(arg2)
        try encoder.recordArgument(arg3)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Verify envelope
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        
        #expect(envelope.arguments.count == 3)
        
        // Decode arguments back
        let decodedArg1 = try decoder.decode(String.self, from: envelope.arguments[0])
        let decodedArg2 = try decoder.decode(Int.self, from: envelope.arguments[1])
        let decodedArg3 = try decoder.decode(Bool.self, from: envelope.arguments[2])
        
        #expect(decodedArg1 == "Hello")
        #expect(decodedArg2 == 42)
        #expect(decodedArg3 == true)
    }
    
    @Test("Encode complex types")
    func testEncodeComplexTypes() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
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
        
        let data = try encoder.getEncodedData()
        
        // Decode and verify
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        
        let decodedMessage = try decoder.decode(ComplexMessage.self, from: envelope.arguments[0])
        #expect(decodedMessage.id == message.id)
        // Date comparison with tolerance due to ISO8601 encoding
        let timeDifference = abs(decodedMessage.timestamp.timeIntervalSince(message.timestamp))
        #expect(timeDifference < 1.0)
        #expect(decodedMessage.data == message.data)
        #expect(decodedMessage.optional == message.optional)
    }
    
    @Test("Encode generic substitutions")
    func testEncodeGenericSubstitutions() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        try encoder.recordGenericSubstitution(String.self)
        try encoder.recordGenericSubstitution(Int.self)
        try encoder.recordGenericSubstitution([String: Int].self)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        
        #expect(envelope.genericSubstitutions.count == 3)
        #expect(envelope.genericSubstitutions[0] == "Swift.String")
        #expect(envelope.genericSubstitutions[1] == "Swift.Int")
        #expect(envelope.genericSubstitutions[2].contains("Dictionary"))
    }
    
    @Test("Encode return and error types")
    func testEncodeReturnAndErrorTypes() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        try encoder.recordReturnType(String.self)
        try encoder.recordErrorType(TestError.self)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        
        #expect(envelope.returnType == "Swift.String")
        #expect(envelope.errorType?.contains("TestError") == true)
    }
    
    // MARK: - InvocationDecoder Tests
    
    @Test("Decode simple argument")
    func testDecodeSimpleArgument() async throws {
        // First encode
        var encoder = ActorEdgeInvocationEncoder()
        let message = SimpleMessage(id: 123, message: "Test")
        let argument = RemoteCallArgument(label: nil, name: "arg", value: message)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Then decode
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        let decodedMessage: SimpleMessage = try decoder.decodeNextArgument()
        
        #expect(decodedMessage == message)
    }
    
    @Test("Decode multiple arguments")
    func testDecodeMultipleArguments() async throws {
        // Encode multiple arguments
        var encoder = ActorEdgeInvocationEncoder()
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "First"))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: 123))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: 45.67))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: false))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Decode them back
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        
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
        var encoder = ActorEdgeInvocationEncoder()
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "Only one"))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Try to decode two arguments
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        
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
        let system = ActorEdgeSystem()
        
        // Create encoded data
        var encoder = ActorEdgeInvocationEncoder()
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "arg", value: "Test with system"))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Decode with system
        var decoder = ActorEdgeInvocationDecoder(system: system, payload: data)
        let decoded: String = try decoder.decodeNextArgument()
        
        #expect(decoded == "Test with system")
    }
    
    @Test("Decode with invalid data")
    func testDecodeWithInvalidData() async throws {
        let system = ActorEdgeSystem()
        let invalidData = Data("invalid json".utf8)
        
        // Should not crash, but initialize with empty values
        var decoder = ActorEdgeInvocationDecoder(system: system, payload: invalidData)
        
        // Trying to decode should throw
        do {
            let _: String = try decoder.decodeNextArgument()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    // MARK: - Date Encoding/Decoding Tests
    
    @Test("Date encoding and decoding")
    func testDateEncodingDecoding() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        let now = Date()
        let argument = RemoteCallArgument(label: nil, name: "arg", value: now)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        let decodedDate: Date = try decoder.decodeNextArgument()
        
        // Dates should be equal within second precision (due to ISO8601 encoding)
        let difference = abs(decodedDate.timeIntervalSince(now))
        #expect(difference < 1.0)
    }
    
    // MARK: - Array and Dictionary Tests
    
    @Test("Array encoding and decoding")
    func testArrayEncodingDecoding() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        let array = [1, 2, 3, 4, 5]
        let argument = RemoteCallArgument(label: nil, name: "arg", value: array)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        let decodedArray: [Int] = try decoder.decodeNextArgument()
        
        #expect(decodedArray == array)
    }
    
    @Test("Dictionary encoding and decoding")
    func testDictionaryEncodingDecoding() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        let dict = ["apple": 1, "banana": 2, "cherry": 3]
        let argument = RemoteCallArgument(label: nil, name: "arg", value: dict)
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        let decodedDict: [String: Int] = try decoder.decodeNextArgument()
        
        #expect(decodedDict == dict)
    }
    
    // MARK: - Performance Tests
    
    @Test("Performance of large payload encoding")
    func testLargePayloadPerformance() async throws {
        var encoder = ActorEdgeInvocationEncoder()
        
        // Create a large array
        let largeArray = Array(0..<1000).map { SimpleMessage(id: $0, message: "Message \($0)") }
        let argument = RemoteCallArgument(label: nil, name: "arg", value: largeArray)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        let data = try encoder.getEncodedData()
        
        let encodingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Decoding
        let decodeStartTime = CFAbsoluteTimeGetCurrent()
        var decoder = try ActorEdgeInvocationDecoder(data: data)
        let decoded: [SimpleMessage] = try decoder.decodeNextArgument()
        let decodingTime = CFAbsoluteTimeGetCurrent() - decodeStartTime
        
        #expect(decoded.count == 1000)
        #expect(encodingTime < 0.1, "Encoding should complete within 100ms")
        #expect(decodingTime < 0.1, "Decoding should complete within 100ms")
    }
}

// MARK: - Helper Types

/// Container for all invocation data (matching the private type in the implementation)
private struct InvocationEnvelope: Codable {
    let arguments: [Data]
    let genericSubstitutions: [String]
    let returnType: String?
    let errorType: String?
}