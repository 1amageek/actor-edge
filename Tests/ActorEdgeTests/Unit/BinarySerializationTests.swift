import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for binary serialization functionality
@Suite("Binary Serialization Tests")
struct BinarySerializationTests {
    
    // MARK: - Test Types
    
    struct TestMessage: Codable, Sendable, Equatable {
        let id: Int
        let text: String
        let timestamp: Date
    }
    
    // MARK: - Binary Encoder Tests
    
    @Test("Encode simple types with binary format")
    func testBinaryEncodeSimpleTypes() async throws {
        var encoder = BinaryInvocationEncoder()
        
        let arg1 = RemoteCallArgument(label: nil, name: "text", value: "Hello")
        let arg2 = RemoteCallArgument(label: "count", name: "count", value: 42)
        let arg3 = RemoteCallArgument(label: nil, name: "flag", value: true)
        
        try encoder.recordArgument(arg1)
        try encoder.recordArgument(arg2)
        try encoder.recordArgument(arg3)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Verify magic bytes
        #expect(data.prefix(4) == Data("AEDG".utf8))
        
        // Verify version
        #expect(data[4] == 1)
        
        // Verify argument count (3)
        var argumentCount: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &argumentCount) { bytes in
            data[5..<9].copyBytes(to: bytes)
        }
        argumentCount = argumentCount.littleEndian
        #expect(argumentCount == 3)
    }
    
    @Test("Encode complex message with binary format")
    func testBinaryEncodeComplexMessage() async throws {
        var encoder = BinaryInvocationEncoder()
        
        let message = TestMessage(
            id: 123,
            text: "Test message",
            timestamp: Date()
        )
        
        let argument = RemoteCallArgument(label: nil, name: "message", value: message)
        try encoder.recordArgument(argument)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        #expect(!data.isEmpty)
        #expect(data.count > 13) // Header is 13 bytes minimum
    }
    
    @Test("Encode generic substitutions")
    func testBinaryEncodeGenericSubstitutions() async throws {
        var encoder = BinaryInvocationEncoder()
        
        try encoder.recordGenericSubstitution(String.self)
        try encoder.recordGenericSubstitution(Int.self)
        try encoder.recordGenericSubstitution([String: Int].self)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Verify generic substitution count (3)
        var genericCount: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &genericCount) { bytes in
            data[9..<13].copyBytes(to: bytes)
        }
        genericCount = genericCount.littleEndian
        #expect(genericCount == 3)
    }
    
    @Test("Encode return and error types")
    func testBinaryEncodeReturnAndErrorTypes() async throws {
        var encoder = BinaryInvocationEncoder()
        
        try encoder.recordReturnType(String.self)
        try encoder.recordErrorType(ActorEdgeError.self)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        #expect(!data.isEmpty)
    }
    
    // MARK: - Binary Decoder Tests
    
    @Test("Decode simple types from binary format")
    func testBinaryDecodeSimpleTypes() async throws {
        // First encode
        var encoder = BinaryInvocationEncoder()
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "text", value: "Hello"))
        try encoder.recordArgument(RemoteCallArgument(label: "count", name: "count", value: 42))
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "flag", value: true))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Then decode
        var decoder = try BinaryInvocationDecoder(data: data)
        
        let text: String = try decoder.decodeNextArgument()
        let count: Int = try decoder.decodeNextArgument()
        let flag: Bool = try decoder.decodeNextArgument()
        
        #expect(text == "Hello")
        #expect(count == 42)
        #expect(flag == true)
    }
    
    @Test("Decode complex message from binary format")
    func testBinaryDecodeComplexMessage() async throws {
        // Encode
        var encoder = BinaryInvocationEncoder()
        let originalMessage = TestMessage(
            id: 456,
            text: "Binary test",
            timestamp: Date()
        )
        
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "message", value: originalMessage))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Decode
        var decoder = try BinaryInvocationDecoder(data: data)
        let decodedMessage: TestMessage = try decoder.decodeNextArgument()
        
        #expect(decodedMessage.id == originalMessage.id)
        #expect(decodedMessage.text == originalMessage.text)
        // Date comparison with tolerance
        let timeDiff = abs(decodedMessage.timestamp.timeIntervalSince(originalMessage.timestamp))
        #expect(timeDiff < 1.0)
    }
    
    @Test("Decode with system initializer")
    func testBinaryDecodeWithSystem() async throws {
        let system = ActorEdgeSystem()
        
        // Create encoded data
        var encoder = BinaryInvocationEncoder()
        try encoder.recordArgument(RemoteCallArgument(label: nil, name: "test", value: "System decode"))
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Decode with system
        var decoder = BinaryInvocationDecoder(system: system, payload: data)
        let decoded: String = try decoder.decodeNextArgument()
        
        #expect(decoded == "System decode")
    }
    
    @Test("Decode error with invalid magic bytes")
    func testBinaryDecodeInvalidMagic() async throws {
        let invalidData = Data("BADM".utf8) + Data(repeating: 0, count: 9)
        
        do {
            _ = try BinaryInvocationDecoder(data: invalidData)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
            if case .invalidFormat(let message) = error as? ActorEdgeError {
                #expect(message.contains("magic"))
            }
        }
    }
    
    @Test("Decode error with unsupported version")
    func testBinaryDecodeUnsupportedVersion() async throws {
        var invalidData = Data("AEDG".utf8)
        invalidData.append(99) // Invalid version
        invalidData.append(Data(repeating: 0, count: 8))
        
        do {
            _ = try BinaryInvocationDecoder(data: invalidData)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
            if case .invalidFormat(let message) = error as? ActorEdgeError {
                #expect(message.contains("version"))
            }
        }
    }
    
    @Test("Decode error with truncated data")
    func testBinaryDecodeTruncatedData() async throws {
        let truncatedData = Data("AEDG".utf8) + Data([1]) // Only 5 bytes
        
        do {
            _ = try BinaryInvocationDecoder(data: truncatedData)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Round-trip encoding and decoding")
    func testBinaryRoundTrip() async throws {
        // Create test data
        let messages = [
            TestMessage(id: 1, text: "First", timestamp: Date()),
            TestMessage(id: 2, text: "Second", timestamp: Date()),
            TestMessage(id: 3, text: "Third", timestamp: Date())
        ]
        
        // Encode
        var encoder = BinaryInvocationEncoder()
        
        try encoder.recordGenericSubstitution(TestMessage.self)
        for (index, message) in messages.enumerated() {
            let argument = RemoteCallArgument(
                label: index == 1 ? "labeled" : nil,
                name: "message\(index)",
                value: message
            )
            try encoder.recordArgument(argument)
        }
        try encoder.recordReturnType([TestMessage].self)
        try encoder.recordErrorType(ActorEdgeError.self)
        try encoder.doneRecording()
        
        let data = try encoder.getEncodedData()
        
        // Decode
        var decoder = try BinaryInvocationDecoder(data: data)
        
        _ = try decoder.decodeGenericSubstitutions()
        
        let decoded1: TestMessage = try decoder.decodeNextArgument()
        let decoded2: TestMessage = try decoder.decodeNextArgument()
        let decoded3: TestMessage = try decoder.decodeNextArgument()
        
        #expect(decoded1.id == messages[0].id)
        #expect(decoded2.id == messages[1].id)
        #expect(decoded3.id == messages[2].id)
    }
    
    // MARK: - Performance Tests
    
    @Test("Binary format performance vs JSON")
    func testBinaryPerformanceComparison() async throws {
        let testCount = 100
        let largeMessage = TestMessage(
            id: 12345,
            text: String(repeating: "Test ", count: 100),
            timestamp: Date()
        )
        
        // Binary encoding performance
        let binaryStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<testCount {
            var encoder = BinaryInvocationEncoder()
            try encoder.recordArgument(RemoteCallArgument(label: nil, name: "msg", value: largeMessage))
            try encoder.doneRecording()
            _ = try encoder.getEncodedData()
        }
        let binaryTime = CFAbsoluteTimeGetCurrent() - binaryStartTime
        
        // JSON encoding performance (current implementation)
        let jsonStartTime = CFAbsoluteTimeGetCurrent()
        for _ in 0..<testCount {
            var encoder = ActorEdgeInvocationEncoder()
            try encoder.recordArgument(RemoteCallArgument(label: nil, name: "msg", value: largeMessage))
            try encoder.doneRecording()
            _ = try encoder.getEncodedData()
        }
        let jsonTime = CFAbsoluteTimeGetCurrent() - jsonStartTime
        
        // Binary should be reasonably fast
        #expect(binaryTime < jsonTime * 2.0, "Binary encoding should not be significantly slower than JSON")
    }
    
    @Test("Binary format size comparison")
    func testBinarySizeComparison() async throws {
        let message = TestMessage(
            id: 999,
            text: "Size comparison test",
            timestamp: Date()
        )
        
        // Binary format
        var binaryEncoder = BinaryInvocationEncoder()
        try binaryEncoder.recordArgument(RemoteCallArgument(label: nil, name: "msg", value: message))
        try binaryEncoder.doneRecording()
        let binaryData = try binaryEncoder.getEncodedData()
        
        // JSON format
        var jsonEncoder = ActorEdgeInvocationEncoder()
        try jsonEncoder.recordArgument(RemoteCallArgument(label: nil, name: "msg", value: message))
        try jsonEncoder.doneRecording()
        let jsonData = try jsonEncoder.getEncodedData()
        
        // Binary format includes more metadata but should still be reasonable
        #expect(binaryData.count < Int(Double(jsonData.count) * 1.5), "Binary format should not be significantly larger")
    }
}