import Testing
import Foundation
import Distributed
import ServiceLifecycle
import Logging
@testable import ActorEdgeCore
@testable import ActorEdgeServer
@testable import ActorEdgeClient

// MARK: - Test Types (must be outside for @Resolvable)

/// Integration test message type
struct IntegrationTestMessage: Codable, Sendable, Equatable {
    let id: Int
    let content: String
    let timestamp: Date
}

// MARK: - Test Protocols (must be outside for @Resolvable)

/// Test chat protocol
@Resolvable
protocol TestChat: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func sendMessage(_ text: String) async throws -> String
    distributed func getMessageCount() async throws -> Int
    distributed func echo(_ message: IntegrationTestMessage) async throws -> IntegrationTestMessage
}

/// Protocol for failing actor
@Resolvable
protocol FailingTest: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func alwaysFails() async throws -> String
}

/// Integration tests for ActorEdge end-to-end functionality
@Suite("Integration Tests")
struct IntegrationTests {
    
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
        
        distributed func echo(_ message: IntegrationTestMessage) async throws -> IntegrationTestMessage {
            // Echo back with modified timestamp
            return IntegrationTestMessage(
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
    static func createConnectedSystems() async -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
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
        
        // Give the server handler task a moment to start
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        return (clientSystem, serverSystem)
    }
    
    /// Handle server-side envelope processing
    static func handleServerEnvelope(_ envelope: Envelope, serverSystem: ActorEdgeSystem, transport: MessageTransport) async {
        do {
            // Process the invocation
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            var decoder = try processor.createInvocationDecoder(from: envelope, system: serverSystem)
            
            // Find the target actor
            guard let actor = await serverSystem.registry?.find(id: envelope.recipient) else {
                throw ActorEdgeError.actorNotFound(envelope.recipient)
            }
            
            // Create response handler that sends back through transport
            let resultHandler = TestResultHandler(transport: transport, requestEnvelope: envelope)
            
            // Get the target method
            let _ = RemoteCallTarget(envelope.metadata.target)
            
            // For integration tests, manually dispatch to known methods
            // In real implementation, Swift runtime would handle this
            if let testChatActor = actor as? TestChatActor {
                // Match against mangled method names
                if envelope.metadata.target.contains("sendMessage") {
                    let text: String = try decoder.decodeNextArgument()
                    let response = try await testChatActor.sendMessage(text)
                    try await resultHandler.onReturn(value: response)
                } else if envelope.metadata.target.contains("getMessageCount") {
                    let count = try await testChatActor.getMessageCount()
                    try await resultHandler.onReturn(value: count)
                } else if envelope.metadata.target.contains("echo") {
                    let message: IntegrationTestMessage = try decoder.decodeNextArgument()
                    let response = try await testChatActor.echo(message)
                    try await resultHandler.onReturn(value: response)
                } else {
                    throw ActorEdgeError.invocationError("Unknown method: \(envelope.metadata.target)")
                }
            } else if let failingActor = actor as? FailingTestActor {
                if envelope.metadata.target.contains("alwaysFails") {
                    do {
                        let response = try await failingActor.alwaysFails()
                        try await resultHandler.onReturn(value: response)
                    } catch {
                        try await resultHandler.onThrow(error: error)
                    }
                } else {
                    throw ActorEdgeError.invocationError("Unknown method: \(envelope.metadata.target)")
                }
            } else {
                throw ActorEdgeError.invocationError("Unknown actor type")
            }
        } catch {
            // Send error response
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            let errorEnvelope = try! processor.createErrorEnvelope(
                to: envelope.sender ?? envelope.recipient,
                correlationID: envelope.metadata.callID,
                error: error,
                sender: envelope.recipient
            )
            _ = try? await transport.send(errorEnvelope)
        }
    }
    
    // MARK: - Integration Tests
    
    @Test("Basic client-server communication")
    func testBasicCommunication() async throws {
        let (clientSystem, serverSystem) = await Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        
        // Wait for actor to be registered
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Get reference on client side
        let clientRef = try $TestChat.resolve(id: serverActor.id, using: clientSystem)
        
        // Call distributed method
        let response = try await clientRef.sendMessage("Hello from client")
        
        #expect(response == "Received: Hello from client (message #1)")
        
        // Test message count
        let count = try await clientRef.getMessageCount()
        #expect(count == 1)
    }
    
    @Test("Complex type serialization")
    func testComplexTypeSerialization() async throws {
        let (clientSystem, serverSystem) = await Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        
        // Get reference on client side
        let clientRef = try $TestChat.resolve(id: serverActor.id, using: clientSystem)
        
        // Create complex message
        let originalMessage = IntegrationTestMessage(
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
        try await withThrowingTaskGroup(of: String.self) { group in
            for (index, (clientSystem, _)) in clientSystems.enumerated() {
                group.addTask {
                    let clientRef = try $TestChat.resolve(id: serverActor.id, using: clientSystem)
                    return try await clientRef.sendMessage("Message from client \(index)")
                }
            }
            
            var responses: [String] = []
            for try await response in group {
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
        let (clientSystem, serverSystem) = await Self.createConnectedSystems()
        
        // Create a failing actor
        let failingActor = FailingTestActor(actorSystem: serverSystem)
        
        // Wait for actor to be registered
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Get reference on client side
        let clientRef = try $FailingTest.resolve(id: failingActor.id, using: clientSystem)
        
        // Call method that throws
        do {
            _ = try await clientRef.alwaysFails()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Remote errors are wrapped in ActorEdgeError
            #expect(error is ActorEdgeError)
            // The actual error message is preserved in the remote call error
            if case ActorEdgeError.remoteCallError(let message) = error {
                #expect(message.contains("This method always fails"))
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Throughput performance")
    func testThroughputPerformance() async throws {
        let (clientSystem, serverSystem) = await Self.createConnectedSystems()
        
        // Create server actor
        let serverActor = TestChatActor(actorSystem: serverSystem)
        let clientRef = try $TestChat.resolve(id: serverActor.id, using: clientSystem)
        
        let messageCount = 100
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Send many messages
        for i in 0..<messageCount {
            _ = try await clientRef.sendMessage("Message \(i)")
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let throughput = Double(messageCount) / duration
        
        #expect(throughput > 50, "Should handle > 50 messages per second")
        
        // Verify all messages were received
        let finalCount = try await clientRef.getMessageCount()
        #expect(finalCount == messageCount)
    }
}

    // MARK: - Additional Test Actors
    
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
    private let serialization: SerializationSystem
    
    init(transport: MessageTransport, requestEnvelope: Envelope) {
        self.transport = transport
        self.requestEnvelope = requestEnvelope
        self.serialization = SerializationSystem()
    }
    
    public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
        // Serialize the value
        let serializedValue = try serialization.serialize(value)
        
        // Wrap in InvocationResult
        let result = InvocationResult.success(serializedValue)
        let resultData = try serialization.serialize(result)
        
        // Create response envelope
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(response)
    }
    
    public func onReturnVoid() async throws {
        // Create void result
        let result = InvocationResult.void
        let resultData = try serialization.serialize(result)
        
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(response)
    }
    
    public func onThrow<Err: Error>(error: Err) async throws {
        // Create error result
        let serializedError: SerializedError
        if let codableError = error as? (any Codable & Error) {
            let errorData = try serialization.serialize(codableError)
            serializedError = SerializedError(
                type: String(reflecting: type(of: error)),
                message: String(describing: error),
                serializedError: errorData.data
            )
        } else {
            serializedError = SerializedError(
                type: String(reflecting: type(of: error)),
                message: String(describing: error),
                serializedError: nil
            )
        }
        
        let result = InvocationResult.error(serializedError)
        let resultData = try serialization.serialize(result)
        
        let errorEnvelope = Envelope.error(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(errorEnvelope)
    }
}

// MARK: - Test Error Type

enum IntegrationTestError: Error, Codable {
    case simulatedError(String)
}