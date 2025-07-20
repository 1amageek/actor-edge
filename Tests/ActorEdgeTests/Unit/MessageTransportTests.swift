import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for MessageTransport protocol functionality
@Suite("MessageTransport Tests")
struct MessageTransportTests {
    
    // MARK: - Test Data
    
    struct TestData {
        static let actorID = ActorEdgeID()
        static let senderID = ActorEdgeID()
        static let targetMethod = "testMethod"
        static let payload = Data("test payload".utf8)
    }
    
    // MARK: - Protocol Conformance Tests
    
    @Test("MessageTransport protocol requirements")
    func testProtocolRequirements() async throws {
        let transport: any MessageTransport = TestableMessageTransport()
        
        // Test required methods exist
        let envelope = createTestEnvelope()
        _ = try await transport.send(envelope)
        _ = transport.receive()
        try await transport.close()
        
        // Test required properties exist
        _ = transport.isConnected
        _ = transport.metadata
        
        #expect(true) // If we get here, all requirements are satisfied
    }
    
    // MARK: - Send/Receive Tests
    
    @Test("Send and receive basic envelope")
    func testSendReceiveBasic() async throws {
        let transport = TestableMessageTransport()
        let envelope = createTestEnvelope()
        
        // Send should return nil for void calls
        let response = try await transport.send(envelope)
        #expect(response == nil)
        
        // Verify envelope was recorded
        #expect(transport.sentEnvelopes.count == 1)
        #expect(transport.sentEnvelopes.first?.metadata.callID == envelope.metadata.callID)
    }
    
    @Test("Send with response")
    func testSendWithResponse() async throws {
        let transport = TestableMessageTransport()
        let requestEnvelope = createTestEnvelope()
        let responseData = Data("response data".utf8)
        
        // Configure mock response
        transport.mockResponse = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: responseData
        )
        
        let response = try await transport.send(requestEnvelope)
        
        #expect(response != nil)
        #expect(response?.payload == responseData)
        #expect(response?.metadata.callID == requestEnvelope.metadata.callID)
        #expect(response?.messageType == .response)
    }
    
    @Test("Receive stream functionality")
    func testReceiveStream() async throws {
        let transport = TestableMessageTransport()
        
        // Enqueue test envelopes
        let envelopes = (0..<5).map { i in
            Envelope.invocation(
                to: TestData.actorID,
                target: "method-\(i)",
                manifest: SerializationManifest(serializerID: "json"),
                payload: Data("payload-\(i)".utf8)
            )
        }
        
        for envelope in envelopes {
            transport.enqueueForReceive(envelope)
        }
        
        // Receive envelopes
        let stream = transport.receive()
        var receivedCount = 0
        
        for await envelope in stream {
            #expect(envelope.metadata.target == "method-\(receivedCount)")
            receivedCount += 1
            
            if receivedCount == envelopes.count {
                break
            }
        }
        
        #expect(receivedCount == envelopes.count)
    }
    
    // MARK: - Connection Management Tests
    
    @Test("Connection state management")
    func testConnectionState() async throws {
        let transport = TestableMessageTransport()
        
        #expect(transport.isConnected == true)
        
        try await transport.close()
        
        #expect(transport.isConnected == false)
    }
    
    @Test("Send after close throws error")
    func testSendAfterClose() async throws {
        let transport = TestableMessageTransport()
        let envelope = createTestEnvelope()
        
        try await transport.close()
        
        do {
            _ = try await transport.send(envelope)
            #expect(Bool(false), "Should throw disconnected error")
        } catch {
            #expect(error is TransportError)
            if let transportError = error as? TransportError {
                if case .disconnected = transportError {
                    #expect(true)
                } else {
                    #expect(Bool(false), "Expected disconnected error")
                }
            }
        }
    }
    
    // MARK: - Metadata Tests
    
    @Test("Transport metadata")
    func testTransportMetadata() async throws {
        let transport = TestableMessageTransport()
        let metadata = transport.metadata
        
        #expect(metadata.transportType == "testable")
        #expect(metadata.endpoint == "test://localhost")
        #expect(metadata.isSecure == false)
        #expect(metadata.attributes["version"] == "1.0")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Send error handling")
    func testSendErrorHandling() async throws {
        let transport = TestableMessageTransport()
        transport.shouldFailSend = true
        
        let envelope = createTestEnvelope()
        
        do {
            _ = try await transport.send(envelope)
            #expect(Bool(false), "Should throw send error")
        } catch {
            #expect(error is TransportError)
            if let transportError = error as? TransportError {
                if case .sendFailed = transportError {
                    #expect(true)
                } else {
                    #expect(Bool(false), "Expected sendFailed error")
                }
            }
        }
    }
    
    // MARK: - Concurrent Operations Tests
    
    @Test("Concurrent sends")
    func testConcurrentSends() async throws {
        let transport = TestableMessageTransport()
        let envelopeCount = 10
        var responseCount = 0
        
        // Create response for each request
        transport.shouldReturnMockResponse = true
        
        await withTaskGroup(of: Envelope?.self) { group in
            for i in 0..<envelopeCount {
                group.addTask {
                    let envelope = Envelope.invocation(
                        to: TestData.actorID,
                        target: "concurrent-\(i)",
                        callID: "call-\(i)",
                        manifest: SerializationManifest(serializerID: "json"),
                        payload: Data("data-\(i)".utf8)
                    )
                    
                    return try? await transport.send(envelope)
                }
            }
            
            for await response in group {
                if response != nil {
                    responseCount += 1
                }
            }
            
            #expect(responseCount <= envelopeCount)
        }
        
        // The actual sent count should match the successful responses
        #expect(transport.sentEnvelopes.count == responseCount)
    }
    
    // MARK: - Helper Functions
    
    private func createTestEnvelope() -> Envelope {
        Envelope.invocation(
            to: TestData.actorID,
            from: TestData.senderID,
            target: TestData.targetMethod,
            manifest: SerializationManifest(serializerID: "json"),
            payload: TestData.payload
        )
    }
}

// MARK: - Testable MessageTransport Implementation

/// A testable implementation of MessageTransport for unit testing
final class TestableMessageTransport: MessageTransport, @unchecked Sendable {
    private(set) var sentEnvelopes: [Envelope] = []
    private var receiveQueue: [Envelope] = []
    private var connected = true
    
    var mockResponse: Envelope?
    var shouldFailSend = false
    var shouldReturnMockResponse = false
    
    func send(_ envelope: Envelope) async throws -> Envelope? {
        guard connected else {
            throw TransportError.disconnected
        }
        
        if shouldFailSend {
            throw TransportError.sendFailed(reason: "Test failure")
        }
        
        sentEnvelopes.append(envelope)
        
        if shouldReturnMockResponse || mockResponse != nil {
            return mockResponse ?? Envelope.response(
                to: envelope.sender ?? envelope.recipient,
                callID: envelope.metadata.callID,
                manifest: SerializationManifest(serializerID: "json"),
                payload: Data("mock response".utf8)
            )
        }
        
        return nil
    }
    
    func receive() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            for envelope in receiveQueue {
                continuation.yield(envelope)
            }
            receiveQueue.removeAll()
            
            // Keep stream open unless disconnected
            if !connected {
                continuation.finish()
            }
        }
    }
    
    func close() async throws {
        connected = false
        receiveQueue.removeAll()
        sentEnvelopes.removeAll()
    }
    
    var isConnected: Bool {
        connected
    }
    
    var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "testable",
            attributes: ["version": "1.0", "test": "true"],
            endpoint: "test://localhost",
            isSecure: false
        )
    }
    
    // Test helper methods
    func enqueueForReceive(_ envelope: Envelope) {
        receiveQueue.append(envelope)
    }
    
    func reset() {
        sentEnvelopes.removeAll()
        receiveQueue.removeAll()
        mockResponse = nil
        shouldFailSend = false
        shouldReturnMockResponse = false
        connected = true
    }
}