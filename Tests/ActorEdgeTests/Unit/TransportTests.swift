import Testing
import Foundation
import Distributed
import ServiceContextModule
import GRPCCore
@testable import ActorEdgeCore

/// Test suite for ActorEdge transport functionality
@Suite("Transport Tests")
struct TransportTests {
    
    // MARK: - Test Configuration
    
    struct TestConfig {
        static let testEndpoint = "127.0.0.1:9999"
        static let testActorID = ActorEdgeID()
        static let testMethod = "testMethod"
        static let testData = Data("test data".utf8)
        static let testCallID = "test-call-123"
    }
    
    // MARK: - Mock Transport Tests
    
    @Test("Mock transport remote call")
    func testMockTransportRemoteCall() async throws {
        let transport = MockTransport()
        let expectedResponse = Data("response".utf8)
        
        // Create response envelope
        let responseEnvelope = Envelope.response(
            to: TestConfig.testActorID,
            callID: TestConfig.testCallID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: expectedResponse
        )
        transport.mockResponse = responseEnvelope
        
        // Create request envelope
        let requestEnvelope = Envelope.invocation(
            to: TestConfig.testActorID,
            target: TestConfig.testMethod,
            callID: TestConfig.testCallID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: TestConfig.testData
        )
        
        let response = try await transport.send(requestEnvelope)
        
        #expect(response?.payload == expectedResponse)
        #expect(transport.lastEnvelope?.recipient == TestConfig.testActorID)
        #expect(transport.lastEnvelope?.metadata.target == TestConfig.testMethod)
        #expect(transport.lastEnvelope?.payload == TestConfig.testData)
    }
    
    @Test("Mock transport remote call void")
    func testMockTransportRemoteCallVoid() async throws {
        let transport = MockTransport()
        
        // Create request envelope for void call
        let requestEnvelope = Envelope.invocation(
            to: TestConfig.testActorID,
            target: TestConfig.testMethod,
            callID: TestConfig.testCallID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: TestConfig.testData
        )
        
        let response = try await transport.send(requestEnvelope)
        
        #expect(response == nil) // Void calls return nil
        #expect(transport.voidCallCount == 1)
        #expect(transport.lastEnvelope?.recipient == TestConfig.testActorID)
        #expect(transport.lastEnvelope?.metadata.target == TestConfig.testMethod)
    }
    
    @Test("Mock transport stream receive")
    func testMockTransportStreamReceive() async throws {
        let transport = MockTransport()
        let streamData = [Data("chunk1".utf8), Data("chunk2".utf8), Data("chunk3".utf8)]
        
        // Enqueue stream envelopes
        for (index, data) in streamData.enumerated() {
            let envelope = Envelope.invocation(
                to: TestConfig.testActorID,
                target: "stream-\(index)",
                manifest: SerializationManifest(serializerID: "json"),
                payload: data
            )
            transport.enqueueReceiveEnvelope(envelope)
        }
        
        let stream = transport.receive()
        var receivedEnvelopes: [Envelope] = []
        
        for await envelope in stream {
            receivedEnvelopes.append(envelope)
            if receivedEnvelopes.count == streamData.count {
                break
            }
        }
        
        #expect(receivedEnvelopes.count == streamData.count)
        #expect(receivedEnvelopes.map { $0.payload } == streamData)
    }
    
    @Test("Mock transport error handling")
    func testMockTransportError() async throws {
        let transport = MockTransport()
        transport.shouldThrowError = true
        
        let requestEnvelope = Envelope.invocation(
            to: TestConfig.testActorID,
            target: TestConfig.testMethod,
            manifest: SerializationManifest(serializerID: "json"),
            payload: TestConfig.testData
        )
        
        do {
            _ = try await transport.send(requestEnvelope)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is TransportError)
        }
    }
    
    // MARK: - Service Context Propagation Tests
    
    @Test("Service context propagation through envelope headers")
    func testServiceContextPropagation() async throws {
        let transport = MockTransport()
        
        // Create envelope with context headers
        let requestEnvelope = Envelope.invocation(
            to: TestConfig.testActorID,
            target: TestConfig.testMethod,
            manifest: SerializationManifest(serializerID: "json"),
            payload: TestConfig.testData,
            headers: [
                "trace-id": "test-trace-123",
                "correlation-id": "test-correlation-456"
            ]
        )
        
        _ = try await transport.send(requestEnvelope)
        
        #expect(transport.lastEnvelope?.metadata.headers["trace-id"] == "test-trace-123")
        #expect(transport.lastEnvelope?.metadata.headers["correlation-id"] == "test-correlation-456")
    }
    
    // MARK: - MessageTransport Protocol Conformance Tests
    
    @Test("Transport conforms to MessageTransport protocol")
    func testTransportConformance() async throws {
        let transport = MockTransport()
        
        // Test that MockTransport conforms to MessageTransport
        let _: any MessageTransport = transport
        
        // Test that it's Sendable
        let _: any Sendable = transport
        
        // Test required properties
        #expect(transport.isConnected == true)
        #expect(transport.metadata.transportType == "mock")
        
        #expect(true) // If we get here, conformance is correct
    }
    
    // MARK: - Performance Tests
    
    @Test("Transport call performance")
    func testTransportPerformance() async throws {
        let transport = MockTransport()
        let responseData = Data("performance test".utf8)
        
        transport.mockResponse = Envelope.response(
            to: TestConfig.testActorID,
            callID: TestConfig.testCallID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: responseData
        )
        
        let iterations = 100
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let envelope = Envelope.invocation(
                to: TestConfig.testActorID,
                target: TestConfig.testMethod,
                callID: "call-\(i)",
                manifest: SerializationManifest(serializerID: "json"),
                payload: TestConfig.testData
            )
            _ = try await transport.send(envelope)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = duration / Double(iterations)
        
        #expect(averageTime < 0.001, "Average call time should be less than 1ms")
    }
    
    // MARK: - Error Envelope Tests
    
    @Test("Error envelope serialization")
    func testErrorEnvelopeSerialization() async throws {
        let error = TestError.simpleError
        let envelope = ErrorEnvelope(
            typeURL: "test.error.TestError",
            data: try JSONEncoder().encode(error)
        )
        
        #expect(!envelope.typeURL.isEmpty)
        #expect(!envelope.data.isEmpty)
        
        // Verify we can decode the error back
        let decodedError = try JSONDecoder().decode(TestError.self, from: envelope.data)
        #expect(decodedError == error)
    }
}

// MARK: - Mock Transport Implementation

final class MockTransport: MessageTransport, @unchecked Sendable {
    var mockResponse: Envelope?
    var shouldThrowError = false
    var voidCallCount = 0
    var lastEnvelope: Envelope?
    private var connected = true
    private var receiveQueue: [Envelope] = []
    
    func send(_ envelope: Envelope) async throws -> Envelope? {
        if shouldThrowError {
            throw TransportError.sendFailed(reason: "Mock transport error")
        }
        
        if !connected {
            throw TransportError.disconnected
        }
        
        lastEnvelope = envelope
        
        // Count void calls
        if envelope.messageType == .invocation && mockResponse == nil {
            voidCallCount += 1
            return nil
        }
        
        // Return mock response if set
        if var response = mockResponse {
            // Update response to match request call ID
            response = Envelope(
                recipient: envelope.sender ?? envelope.recipient,
                sender: envelope.recipient,
                manifest: response.manifest,
                payload: response.payload,
                metadata: MessageMetadata(
                    callID: envelope.metadata.callID,
                    target: response.metadata.target,
                    headers: response.metadata.headers
                ),
                messageType: response.messageType
            )
            return response
        }
        
        return nil
    }
    
    func receive() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            for envelope in receiveQueue {
                continuation.yield(envelope)
            }
            
            // Keep stream open for future messages
            if connected {
                // In real implementation, this would wait for new messages
                // For testing, we just finish after current queue
                continuation.finish()
            } else {
                continuation.finish()
            }
        }
    }
    
    func close() async throws {
        connected = false
        receiveQueue.removeAll()
    }
    
    var isConnected: Bool {
        connected
    }
    
    var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "mock",
            attributes: ["test": "true"],
            endpoint: "mock://test",
            isSecure: false
        )
    }
    
    // Test helpers
    func enqueueReceiveEnvelope(_ envelope: Envelope) {
        receiveQueue.append(envelope)
    }
    
    func disconnect() {
        connected = false
    }
}

// Test types are imported from TestUtilities.swift
