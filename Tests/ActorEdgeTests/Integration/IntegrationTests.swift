import Testing
import Foundation
import Distributed
import ServiceLifecycle
import Logging
@testable import ActorEdgeCore
@testable import ActorEdgeServer
@testable import ActorEdgeClient

/// Integration tests for ActorEdge end-to-end functionality
@Suite("Integration Tests")
struct IntegrationTests {
    
    // MARK: - Test Types
    
    /// Test message type
    struct TestMessage: Codable, Sendable, Equatable {
        let id: Int
        let content: String
        let timestamp: Date
    }
    
    // MARK: - Test Protocol
    
    /// Test chat protocol
    protocol TestChat: DistributedActor where ActorSystem == ActorEdgeSystem {
        distributed func sendMessage(_ text: String) async throws -> String
        distributed func getMessageCount() async throws -> Int
        distributed func echo(_ message: TestMessage) async throws -> TestMessage
    }
    
    // MARK: - Test Actors
    
    /// Concrete implementation of test chat service
    distributed actor TestChatActor: TestChat {
        public typealias ActorSystem = ActorEdgeSystem
        
        private var messageCount = 0
        
        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }
        
        distributed func sendMessage(_ text: String) async throws -> String {
            messageCount += 1
            return "Received: \(text) (message #\(messageCount))"
        }
        
        distributed func getMessageCount() async throws -> Int {
            return messageCount
        }
        
        distributed func echo(_ message: TestMessage) async throws -> TestMessage {
            // Echo back with modified timestamp
            return TestMessage(
                id: message.id,
                content: message.content,
                timestamp: Date()
            )
        }
    }
    
    // MARK: - Test Server
    
    struct TestServer: Server {
        var port: Int { 9876 }
        
        init() {}
        
        @ActorBuilder
        func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            TestChatActor(actorSystem: actorSystem)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Create connected client and server systems using InMemoryMessageTransport
    static func createConnectedSystems() -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let clientSystem = ActorEdgeSystem(transport: clientTransport)
        let serverSystem = ActorEdgeSystem()
        
        // Set up server transport to handle incoming requests
        Task {
            let stream = serverTransport.receive()
            for await envelope in stream {
                await handleServerEnvelope(envelope, serverSystem: serverSystem, transport: serverTransport)
            }
        }
        
        return (clientSystem, serverSystem)
    }
    
    /// Handle server-side envelope processing
    static func handleServerEnvelope(_ envelope: Envelope, serverSystem: ActorEdgeSystem, transport: MessageTransport) async {
        do {
            // Create response handler that sends back through transport
            let resultHandler = TestResultHandler(transport: transport, requestEnvelope: envelope)
            
            // Process the invocation
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            let _ = try processor.createInvocationDecoder(from: envelope, system: serverSystem)
            
            // Find the target actor
            guard await serverSystem.registry?.find(id: envelope.recipient) != nil else {
                throw ActorEdgeError.actorNotFound(envelope.recipient)
            }
            
            // Execute the distributed target (this would normally be done by Swift runtime)
            // For testing, we'll send a simple response
            try await resultHandler.onReturn(value: "Test response")
        } catch {
            // Send error response
            let errorEnvelope = Envelope.error(
                to: envelope.sender ?? envelope.recipient,
                callID: envelope.metadata.callID,
                manifest: SerializationManifest(serializerID: "json"),
                payload: try! JSONEncoder().encode(error.localizedDescription)
            )
            _ = try? await transport.send(errorEnvelope)
        }
    }
    
    // MARK: - Integration Tests
    
    @Test("Basic client-server communication")
    func testBasicCommunication() async throws {
        let (clientSystem, serverSystem) = Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        
        // Get reference on client side
        let clientRef = try TestChatActor.resolve(id: serverActor.id, using: clientSystem)
        
        // Call distributed method
        let response = try await clientRef.sendMessage("Hello from client")
        
        #expect(response == "Received: Hello from client (message #1)")
        
        // Test message count
        let count = try await clientRef.getMessageCount()
        #expect(count == 1)
    }
    
    @Test("Complex type serialization")
    func testComplexTypeSerialization() async throws {
        let (clientSystem, serverSystem) = Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        
        // Get reference on client side
        let clientRef = try TestChatActor.resolve(id: serverActor.id, using: clientSystem)
        
        // Create complex message
        let originalMessage = TestMessage(
            id: 42,
            content: "Complex message with special characters: 🎉✨",
            timestamp: Date()
        )
        
        // Echo the message
        let echoedMessage = try await clientRef.echo(originalMessage)
        
        #expect(echoedMessage.id == originalMessage.id)
        #expect(echoedMessage.content == originalMessage.content)
        // Timestamp will be different (server creates new one)
        #expect(echoedMessage.timestamp.timeIntervalSince(originalMessage.timestamp) >= 0)
    }
    
    @Test("Multiple concurrent clients")
    func testMultipleConcurrentClients() async throws {
        let serverSystem = ActorEdgeSystem()
        let serverActor = TestChatActor(actorSystem: serverSystem)
        
        // Create multiple client systems
        let clientCount = 5
        var clientSystems: [(system: ActorEdgeSystem, transport: MessageTransport)] = []
        
        for _ in 0..<clientCount {
            let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
            let clientSystem = ActorEdgeSystem(transport: clientTransport)
            clientSystems.append((clientSystem, clientTransport))
            
            // Set up server transport handler
            Task {
                let stream = serverTransport.receive()
                for await envelope in stream {
                    await Self.handleServerEnvelope(envelope, serverSystem: serverSystem, transport: serverTransport)
                }
            }
        }
        
        // Send messages concurrently from all clients
        await withTaskGroup(of: String.self) { group in
            for (index, (clientSystem, _)) in clientSystems.enumerated() {
                group.addTask {
                    let clientRef = try! TestChatActor.resolve(id: serverActor.id, using: clientSystem)
                    return try! await clientRef.sendMessage("Message from client \(index)")
                }
            }
            
            var responses: [String] = []
            for await response in group {
                responses.append(response)
            }
            
            #expect(responses.count == clientCount)
            
            // Verify all messages were received
            for (index, _) in clientSystems.enumerated() {
                #expect(responses.contains { $0.contains("client \(index)") })
            }
        }
        
        // Verify total message count
        let finalCount = try await serverActor.getMessageCount()
        #expect(finalCount == clientCount)
    }
    
    @Test("Error propagation")
    func testErrorPropagation() async throws {
        let (clientSystem, serverSystem) = Self.createConnectedSystems()
        
        // Create a failing actor
        let failingActor = FailingTestActor(actorSystem: serverSystem)
        
        // Get reference on client side
        let clientRef = try FailingTestActor.resolve(id: failingActor.id, using: clientSystem)
        
        // Call method that throws
        do {
            _ = try await clientRef.alwaysFails()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is IntegrationTestError)
            if case IntegrationTestError.simulatedError(let message) = error {
                #expect(message == "This method always fails")
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Throughput performance")
    func testThroughputPerformance() async throws {
        let (clientSystem, serverSystem) = Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        let clientRef = try TestChatActor.resolve(id: serverActor.id, using: clientSystem)
        
        let messageCount = 100
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Send many messages
        for i in 0..<messageCount {
            _ = try await clientRef.sendMessage("Message \(i)")
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(messageCount) / duration
        
        #expect(throughput > 100, "Should handle > 100 messages per second")
        
        // Verify all messages were received
        let finalCount = try await clientRef.getMessageCount()
        #expect(finalCount == messageCount)
    }
}

    // MARK: - Additional Test Actors
    
    /// Protocol for failing actor
    protocol FailingTest: DistributedActor where ActorSystem == ActorEdgeSystem {
        distributed func alwaysFails() async throws -> String
    }
    
    /// Actor that always throws errors
    distributed actor FailingTestActor: FailingTest {
        public typealias ActorSystem = ActorEdgeSystem
        
        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }
        
        distributed func alwaysFails() async throws -> String {
            throw IntegrationTestError.simulatedError("This method always fails")
        }
    }

// MARK: - Test Result Handler

/// Result handler for test server responses
final class TestResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable & Sendable
    
    private let transport: MessageTransport
    private let requestEnvelope: Envelope
    
    init(transport: MessageTransport, requestEnvelope: Envelope) {
        self.transport = transport
        self.requestEnvelope = requestEnvelope
    }
    
    public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
        let payload = try JSONEncoder().encode(value)
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: payload
        )
        _ = try await transport.send(response)
    }
    
    public func onReturnVoid() async throws {
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: Data()
        )
        _ = try await transport.send(response)
    }
    
    public func onThrow<Err: Error>(error: Err) async throws {
        let errorData = try JSONEncoder().encode(error.localizedDescription)
        
        let errorEnvelope = Envelope.error(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: errorData
        )
        _ = try await transport.send(errorEnvelope)
    }
}

// MARK: - Test Error Type

enum IntegrationTestError: Error, Codable {
    case simulatedError(String)
}