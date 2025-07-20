import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for ActorEdge Envelope functionality
@Suite("Envelope Tests")
struct EnvelopeTests {
    
    // MARK: - Test Data
    
    struct TestData {
        static let actorID = ActorEdgeID()
        static let senderID = ActorEdgeID()
        static let targetMethod = "testMethod"
        static let callID = "test-call-123"
        static let payload = Data("test payload".utf8)
        static let manifest = SerializationManifest(serializerID: "json")
    }
    
    // MARK: - Envelope Creation Tests
    
    @Test("Create invocation envelope")
    func testCreateInvocationEnvelope() async throws {
        let envelope = Envelope.invocation(
            to: TestData.actorID,
            from: TestData.senderID,
            target: TestData.targetMethod,
            callID: TestData.callID,
            manifest: TestData.manifest,
            payload: TestData.payload,
            headers: ["custom": "header"]
        )
        
        #expect(envelope.recipient == TestData.actorID)
        #expect(envelope.sender == TestData.senderID)
        #expect(envelope.metadata.target == TestData.targetMethod)
        #expect(envelope.metadata.callID == TestData.callID)
        #expect(envelope.manifest.serializerID == "json")
        #expect(envelope.payload == TestData.payload)
        #expect(envelope.messageType == .invocation)
        #expect(envelope.metadata.headers["custom"] == "header")
    }
    
    @Test("Create response envelope")
    func testCreateResponseEnvelope() async throws {
        let envelope = Envelope.response(
            to: TestData.actorID,
            from: TestData.senderID,
            callID: TestData.callID,
            manifest: TestData.manifest,
            payload: TestData.payload
        )
        
        #expect(envelope.recipient == TestData.actorID)
        #expect(envelope.sender == TestData.senderID)
        #expect(envelope.metadata.callID == TestData.callID)
        #expect(envelope.metadata.target == "") // Responses don't have targets
        #expect(envelope.manifest.serializerID == "json")
        #expect(envelope.payload == TestData.payload)
        #expect(envelope.messageType == .response)
    }
    
    @Test("Create error envelope")
    func testCreateErrorEnvelope() async throws {
        let errorData = try JSONEncoder().encode(TestError.errorWithMessage("test error"))
        
        let envelope = Envelope.error(
            to: TestData.actorID,
            from: TestData.senderID,
            callID: TestData.callID,
            manifest: TestData.manifest,
            payload: errorData
        )
        
        #expect(envelope.recipient == TestData.actorID)
        #expect(envelope.sender == TestData.senderID)
        #expect(envelope.metadata.callID == TestData.callID)
        #expect(envelope.metadata.target == "") // Errors don't have targets
        #expect(envelope.messageType == .error)
        
        // Verify error can be decoded
        let decodedError = try JSONDecoder().decode(TestError.self, from: envelope.payload)
        #expect(decodedError == TestError.errorWithMessage("test error"))
    }
    
    // MARK: - Envelope Serialization Tests
    
    @Test("Envelope codable conformance")
    func testEnvelopeCodable() async throws {
        let original = Envelope.invocation(
            to: TestData.actorID,
            from: TestData.senderID,
            target: TestData.targetMethod,
            callID: TestData.callID,
            manifest: TestData.manifest,
            payload: TestData.payload,
            headers: ["trace-id": "123456"]
        )
        
        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Envelope.self, from: data)
        
        // Verify
        #expect(decoded.recipient == original.recipient)
        #expect(decoded.sender == original.sender)
        #expect(decoded.metadata.target == original.metadata.target)
        #expect(decoded.metadata.callID == original.metadata.callID)
        #expect(decoded.manifest.serializerID == original.manifest.serializerID)
        #expect(decoded.payload == original.payload)
        #expect(decoded.messageType == original.messageType)
        #expect(decoded.metadata.headers["trace-id"] == "123456")
    }
    
    // MARK: - Message Metadata Tests
    
    @Test("Message metadata creation")
    func testMessageMetadata() async throws {
        let headers = ["trace-id": "abc", "user-id": "123"]
        let metadata = MessageMetadata(
            callID: TestData.callID,
            target: TestData.targetMethod,
            headers: headers
        )
        
        #expect(metadata.callID == TestData.callID)
        #expect(metadata.target == TestData.targetMethod)
        #expect(metadata.headers == headers)
        #expect(metadata.timestamp.timeIntervalSinceNow < 1) // Should be recent
    }
    
    @Test("Message metadata codable")
    func testMessageMetadataCodable() async throws {
        let original = MessageMetadata(
            callID: TestData.callID,
            target: TestData.targetMethod,
            timestamp: Date(timeIntervalSinceNow: -60), // 1 minute ago
            headers: ["key": "value"]
        )
        
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MessageMetadata.self, from: data)
        
        #expect(decoded.callID == original.callID)
        #expect(decoded.target == original.target)
        #expect(decoded.headers == original.headers)
        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 0.001)
    }
    
    // MARK: - Serialization Manifest Tests
    
    @Test("Serialization manifest with all fields")
    func testSerializationManifest() async throws {
        let manifest = SerializationManifest(
            serializerID: "protobuf",
            hint: "com.example.MyType"
        )
        
        #expect(manifest.serializerID == "protobuf")
        #expect(manifest.hint == "com.example.MyType")
    }
    
    @Test("Serialization manifest minimal")
    func testSerializationManifestMinimal() async throws {
        let manifest = SerializationManifest(serializerID: "json")
        
        #expect(manifest.serializerID == "json")
        #expect(manifest.hint == "")
    }
    
    // MARK: - Message Type Tests
    
    @Test("Message type raw values")
    func testMessageTypeRawValues() async throws {
        #expect(MessageType.invocation.rawValue == "invocation")
        #expect(MessageType.response.rawValue == "response")
        #expect(MessageType.error.rawValue == "error")
        #expect(MessageType.system.rawValue == "system")
    }
    
    // MARK: - Edge Case Tests
    
    @Test("Envelope without sender")
    func testEnvelopeWithoutSender() async throws {
        let envelope = Envelope.invocation(
            to: TestData.actorID,
            target: TestData.targetMethod,
            manifest: TestData.manifest,
            payload: TestData.payload
        )
        
        #expect(envelope.sender == nil)
        #expect(envelope.recipient == TestData.actorID)
    }
    
    @Test("Envelope with empty headers")
    func testEnvelopeWithEmptyHeaders() async throws {
        let envelope = Envelope.invocation(
            to: TestData.actorID,
            target: TestData.targetMethod,
            manifest: TestData.manifest,
            payload: TestData.payload
        )
        
        #expect(envelope.metadata.headers.isEmpty)
    }
    
    @Test("Envelope with large payload")
    func testEnvelopeWithLargePayload() async throws {
        // Create 1MB payload
        let largePayload = Data(repeating: 0xFF, count: 1024 * 1024)
        
        let envelope = Envelope.invocation(
            to: TestData.actorID,
            target: TestData.targetMethod,
            manifest: TestData.manifest,
            payload: largePayload
        )
        
        #expect(envelope.payload.count == 1024 * 1024)
        
        // Test serialization with large payload
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(Envelope.self, from: data)
        
        #expect(decoded.payload == largePayload)
    }
    
    // MARK: - Performance Tests
    
    @Test("Envelope creation performance")
    func testEnvelopeCreationPerformance() async throws {
        let iterations = 10000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = Envelope.invocation(
                to: TestData.actorID,
                target: "method-\(i)",
                callID: "call-\(i)",
                manifest: TestData.manifest,
                payload: TestData.payload
            )
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = duration / Double(iterations)
        
        #expect(averageTime < 0.0001, "Average envelope creation should be less than 0.1ms")
    }
    
    @Test("Envelope serialization performance")
    func testEnvelopeSerializationPerformance() async throws {
        let envelope = Envelope.invocation(
            to: TestData.actorID,
            target: TestData.targetMethod,
            manifest: TestData.manifest,
            payload: TestData.payload
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let iterations = 1000
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            let data = try encoder.encode(envelope)
            _ = try decoder.decode(Envelope.self, from: data)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = duration / Double(iterations)
        
        #expect(averageTime < 0.001, "Average serialization round-trip should be less than 1ms")
    }
}

// Use TestError from TestUtilities.swift