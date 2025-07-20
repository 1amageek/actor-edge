import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore

/// Test suite for InMemoryMessageTransport functionality
@Suite("InMemoryMessageTransport Tests")
struct InMemoryMessageTransportTests {
    
    // MARK: - Test Data
    
    struct TestData {
        static let actorID = ActorEdgeID()
        static let senderID = ActorEdgeID()
        static let targetMethod = "testMethod"
        static let payload = Data("test payload".utf8)
        
        static func createEnvelope(target: String = targetMethod) -> Envelope {
            Envelope.invocation(
                to: actorID,
                from: senderID,
                target: target,
                manifest: SerializationManifest(serializerID: "json"),
                payload: payload
            )
        }
    }
    
    // MARK: - Basic Functionality Tests
    
    @Test("Create and configure transport")
    func testCreateTransport() async throws {
        let transport = InMemoryMessageTransport()
        
        #expect(transport.isConnected == true)
        #expect(transport.metadata.transportType == "in-memory")
        #expect(transport.metadata.isSecure == true) // In-memory is inherently secure
        #expect(transport.metadata.endpoint?.starts(with: "memory://") == true)
    }
    
    @Test("Paired transport communication")
    func testPairedTransportCommunication() async throws {
        let clientTransport = InMemoryMessageTransport()
        let serverTransport = InMemoryMessageTransport()
        
        // Pair the transports
        clientTransport.pair(with: serverTransport)
        
        // Send from client
        let envelope = TestData.createEnvelope()
        let sendTask = Task {
            try await clientTransport.send(envelope)
        }
        
        // Receive on server
        let stream = serverTransport.receive()
        var receivedEnvelope: Envelope?
        
        for await received in stream {
            receivedEnvelope = received
            break
        }
        
        // Wait for send to complete
        _ = try await sendTask.value
        
        #expect(receivedEnvelope != nil)
        #expect(receivedEnvelope?.metadata.callID == envelope.metadata.callID)
        #expect(receivedEnvelope?.payload == envelope.payload)
    }
    
    @Test("Create connected pair factory method")
    func testCreateConnectedPair() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        #expect(client.metadata.attributes["paired"] == "true")
        #expect(server.metadata.attributes["paired"] == "true")
        
        // Test communication
        let envelope = TestData.createEnvelope()
        let sendTask = Task {
            try await client.send(envelope)
        }
        
        let stream = server.receive()
        var received = false
        
        for await _ in stream {
            received = true
            break
        }
        
        _ = try await sendTask.value
        #expect(received == true)
    }
    
    // MARK: - Message Handler Tests
    
    @Test("Custom message handler")
    func testCustomMessageHandler() async throws {
        let transport = InMemoryMessageTransport()
        let responseData = Data("custom response".utf8)
        
        // Set custom handler that returns a response
        transport.setMessageHandler { envelope in
            return Envelope.response(
                to: envelope.sender ?? envelope.recipient,
                callID: envelope.metadata.callID,
                manifest: SerializationManifest(serializerID: "json"),
                payload: responseData
            )
        }
        
        let request = TestData.createEnvelope()
        let response = try await transport.send(request)
        
        #expect(response != nil)
        #expect(response?.payload == responseData)
        #expect(response?.messageType == .response)
    }
    
    @Test("Message handler error propagation")
    func testMessageHandlerError() async throws {
        let transport = InMemoryMessageTransport()
        
        transport.setMessageHandler { _ in
            throw TransportError.sendFailed(reason: "Handler error")
        }
        
        let envelope = TestData.createEnvelope()
        
        do {
            _ = try await transport.send(envelope)
            #expect(Bool(false), "Should throw error from handler")
        } catch {
            #expect(error is TransportError)
        }
    }
    
    // MARK: - Request-Response Pattern Tests
    
    @Test("Request-response with paired transports")
    func testRequestResponse() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        // Server handles requests and sends responses
        Task {
            let stream = server.receive()
            for await request in stream {
                if request.messageType == .invocation {
                    let response = Envelope.response(
                        to: request.sender ?? request.recipient,
                        callID: request.metadata.callID,
                        manifest: SerializationManifest(serializerID: "json"),
                        payload: Data("response for \(request.metadata.target)".utf8)
                    )
                    _ = try? await server.send(response)
                }
            }
        }
        
        // Client sends request and waits for response
        let request = TestData.createEnvelope()
        let response = try await client.send(request)
        
        #expect(response != nil)
        #expect(response?.messageType == .response)
        #expect(response?.metadata.callID == request.metadata.callID)
        #expect(String(data: response!.payload, encoding: .utf8) == "response for \(request.metadata.target)")
    }
    
    // MARK: - Queue Management Tests
    
    @Test("Direct message enqueuing")
    func testDirectEnqueuing() async throws {
        let transport = InMemoryMessageTransport()
        
        // Enqueue messages directly
        let envelopes = (0..<5).map { i in
            TestData.createEnvelope(target: "method-\(i)")
        }
        
        for envelope in envelopes {
            await transport.enqueueMessage(envelope)
        }
        
        // Receive enqueued messages
        let stream = transport.receive()
        var receivedCount = 0
        
        for await received in stream {
            #expect(received.metadata.target == "method-\(receivedCount)")
            receivedCount += 1
            
            if receivedCount == envelopes.count {
                break
            }
        }
        
        #expect(receivedCount == envelopes.count)
    }
    
    @Test("Get sent messages for testing")
    func testGetSentMessages() async throws {
        let transport = InMemoryMessageTransport()
        
        // Enqueue some messages as if they were sent
        let envelopes = (0..<3).map { i in
            TestData.createEnvelope(target: "sent-\(i)")
        }
        
        for envelope in envelopes {
            await transport.enqueueMessage(envelope)
        }
        
        let sentMessages = await transport.getSentMessages()
        #expect(sentMessages.count == 3)
    }
    
    @Test("Clear messages")
    func testClearMessages() async throws {
        let transport = InMemoryMessageTransport()
        
        // Add some messages
        await transport.enqueueMessage(TestData.createEnvelope())
        await transport.enqueueMessage(TestData.createEnvelope())
        
        var messages = await transport.getSentMessages()
        #expect(messages.count == 2)
        
        // Clear messages
        await transport.clearMessages()
        
        messages = await transport.getSentMessages()
        #expect(messages.count == 0)
    }
    
    // MARK: - Connection Management Tests
    
    @Test("Close transport")
    func testCloseTransport() async throws {
        let transport = InMemoryMessageTransport()
        
        #expect(transport.isConnected == true)
        
        try await transport.close()
        
        #expect(transport.isConnected == false)
        
        // Verify send fails after close
        do {
            _ = try await transport.send(TestData.createEnvelope())
            #expect(Bool(false), "Should throw disconnected error")
        } catch {
            #expect(error is TransportError)
        }
    }
    
    @Test("Close paired transports")
    func testClosePairedTransports() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        // Close client
        try await client.close()
        
        // Verify metadata updates
        #expect(client.metadata.attributes["paired"] == "false")
        
        // Server should still be connected but unpaired
        #expect(server.isConnected == true)
        #expect(server.metadata.attributes["paired"] == "false")
    }
    
    // MARK: - Concurrent Operations Tests
    
    @Test("Concurrent message handling")
    func testConcurrentMessages() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        // Server echo handler
        server.setMessageHandler { request in
            return Envelope.response(
                to: request.sender ?? request.recipient,
                callID: request.metadata.callID,
                manifest: request.manifest,
                payload: request.payload
            )
        }
        
        // Send multiple concurrent requests
        let requestCount = 10
        
        await withTaskGroup(of: Envelope?.self) { group in
            for i in 0..<requestCount {
                group.addTask {
                    let envelope = Envelope.invocation(
                        to: TestData.actorID,
                        target: "concurrent-\(i)",
                        callID: "call-\(i)",
                        manifest: SerializationManifest(serializerID: "json"),
                        payload: Data("data-\(i)".utf8)
                    )
                    
                    return try? await client.send(envelope)
                }
            }
            
            var responseCount = 0
            for await response in group {
                if let resp = response {
                    #expect(resp.messageType == .response)
                    responseCount += 1
                }
            }
            
            #expect(responseCount == requestCount)
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Message throughput performance")
    func testMessageThroughput() async throws {
        let (client, server) = InMemoryMessageTransport.createConnectedPair()
        
        // Simple echo handler
        server.setMessageHandler { request in
            return Envelope.response(
                to: request.sender ?? request.recipient,
                callID: request.metadata.callID,
                manifest: SerializationManifest(serializerID: "json"),
                payload: Data("ack".utf8)
            )
        }
        
        let messageCount = 1000
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<messageCount {
            let envelope = Envelope.invocation(
                to: TestData.actorID,
                target: "perf-test",
                callID: "perf-\(i)",
                manifest: SerializationManifest(serializerID: "json"),
                payload: TestData.payload
            )
            
            _ = try await client.send(envelope)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(messageCount) / duration
        
        #expect(throughput > 1000, "Should handle > 1000 messages per second")
    }
}