import Testing
import Foundation
import Distributed
import ServiceLifecycle
@testable import ActorEdgeCore
@testable import ActorEdgeServer
@testable import ActorEdgeClient
@testable import SampleChatShared
@testable import SampleChatServer
@testable import SampleChatClient

/// Test suite for the Chat sample application
@Suite("Chat Sample Tests")
struct ChatTests {
    
    // MARK: - Test Configuration
    
    struct TestUser {
        let id: String
        let name: String
        
        static let alice = TestUser(id: "alice", name: "Alice")
        static let bob = TestUser(id: "bob", name: "Bob")
        static let charlie = TestUser(id: "charlie", name: "Charlie")
    }
    
    // MARK: - Server Setup
    
    struct TestChatServer: Server {
        var port: Int { 9999 }
        var host: String { "127.0.0.1" }
        
        init() {}
        
        @ActorBuilder
        func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
            ChatServiceActor(actorSystem: actorSystem)
        }
    }
    
    // MARK: - Chat Service Tests
    
    @Test("Basic chat functionality")
    func testBasicChatFunctionality() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        
        // Wait for actor registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Get client reference
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Join users
        try await chatService.join(userID: TestUser.alice.id, name: TestUser.alice.name)
        try await chatService.join(userID: TestUser.bob.id, name: TestUser.bob.name)
        
        // Send messages
        try await chatService.send(TestUser.alice.id, "Hello from Alice!")
        try await chatService.send(TestUser.bob.id, "Hi Alice, this is Bob!")
        
        // Get message history
        let history = try await chatService.history()
        
        #expect(history.count == 2)
        #expect(history[0].content == "Hello from Alice!")
        #expect(history[0].userID == TestUser.alice.id)
        #expect(history[1].content == "Hi Alice, this is Bob!")
        #expect(history[1].userID == TestUser.bob.id)
    }
    
    @Test("User management")
    func testUserManagement() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Initially no users
        var users = try await chatService.listUsers()
        #expect(users.isEmpty)
        
        // Join users
        try await chatService.join(userID: TestUser.alice.id, name: TestUser.alice.name)
        try await chatService.join(userID: TestUser.bob.id, name: TestUser.bob.name)
        try await chatService.join(userID: TestUser.charlie.id, name: TestUser.charlie.name)
        
        // Verify users
        users = try await chatService.listUsers()
        #expect(users.count == 3)
        #expect(users.contains { $0.id == TestUser.alice.id && $0.name == TestUser.alice.name })
        #expect(users.contains { $0.id == TestUser.bob.id && $0.name == TestUser.bob.name })
        #expect(users.contains { $0.id == TestUser.charlie.id && $0.name == TestUser.charlie.name })
        
        // Leave chat
        try await chatService.leave(TestUser.bob.id)
        
        // Verify user left
        users = try await chatService.listUsers()
        #expect(users.count == 2)
        #expect(!users.contains { $0.id == TestUser.bob.id })
    }
    
    @Test("Message subscription")
    func testMessageSubscription() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Join user
        try await chatService.join(userID: TestUser.alice.id, name: TestUser.alice.name)
        
        // Subscribe to messages
        let messageStream = try await chatService.subscribe(TestUser.alice.id)
        
        // Create a task to collect messages
        let collectorTask = Task {
            var messages: [Message] = []
            for await message in messageStream {
                messages.append(message)
                if messages.count >= 3 {
                    break
                }
            }
            return messages
        }
        
        // Send messages from different users
        try await chatService.join(userID: TestUser.bob.id, name: TestUser.bob.name)
        try await chatService.send(TestUser.bob.id, "Hello Alice!")
        try await chatService.send(TestUser.alice.id, "Hi Bob!")
        try await chatService.send(TestUser.bob.id, "How are you?")
        
        // Wait for messages to be collected
        let collectedMessages = await collectorTask.value
        
        #expect(collectedMessages.count == 3)
        #expect(collectedMessages[0].content == "Hello Alice!")
        #expect(collectedMessages[1].content == "Hi Bob!")
        #expect(collectedMessages[2].content == "How are you?")
    }
    
    @Test("Multiple concurrent subscribers")
    func testMultipleConcurrentSubscribers() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Join users
        try await chatService.join(userID: TestUser.alice.id, name: TestUser.alice.name)
        try await chatService.join(userID: TestUser.bob.id, name: TestUser.bob.name)
        try await chatService.join(userID: TestUser.charlie.id, name: TestUser.charlie.name)
        
        // Subscribe all users
        let aliceStream = try await chatService.subscribe(TestUser.alice.id)
        let bobStream = try await chatService.subscribe(TestUser.bob.id)
        let charlieStream = try await chatService.subscribe(TestUser.charlie.id)
        
        // Create collectors for each stream
        let aliceCollector = createMessageCollector(stream: aliceStream, count: 2)
        let bobCollector = createMessageCollector(stream: bobStream, count: 2)
        let charlieCollector = createMessageCollector(stream: charlieStream, count: 2)
        
        // Send messages
        try await chatService.send(TestUser.alice.id, "Message from Alice")
        try await chatService.send(TestUser.bob.id, "Message from Bob")
        
        // Wait for all collectors
        let aliceMessages = await aliceCollector.value
        let bobMessages = await bobCollector.value
        let charlieMessages = await charlieCollector.value
        
        // All users should receive all messages
        #expect(aliceMessages.count == 2)
        #expect(bobMessages.count == 2)
        #expect(charlieMessages.count == 2)
        
        // Verify message content
        for messages in [aliceMessages, bobMessages, charlieMessages] {
            #expect(messages[0].content == "Message from Alice")
            #expect(messages[1].content == "Message from Bob")
        }
    }
    
    @Test("Error handling - send without joining")
    func testSendWithoutJoining() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Try to send without joining
        do {
            try await chatService.send("unknown-user", "This should fail")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected error
            #expect(error is ActorEdgeError || String(describing: error).contains("not found"))
        }
    }
    
    @Test("Error handling - subscribe without joining")
    func testSubscribeWithoutJoining() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Try to subscribe without joining
        do {
            _ = try await chatService.subscribe("unknown-user")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected error
            #expect(error is ActorEdgeError || String(describing: error).contains("not found"))
        }
    }
    
    @Test("Message ordering")
    func testMessageOrdering() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Join user
        try await chatService.join(userID: TestUser.alice.id, name: TestUser.alice.name)
        
        // Send many messages rapidly
        let messageCount = 50
        for i in 0..<messageCount {
            try await chatService.send(TestUser.alice.id, "Message \(i)")
        }
        
        // Get history
        let history = try await chatService.history()
        
        #expect(history.count == messageCount)
        
        // Verify ordering
        for (index, message) in history.enumerated() {
            #expect(message.content == "Message \(index)")
        }
    }
    
    @Test("Performance - many users")
    func testManyUsers() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        let userCount = 100
        
        // Join many users
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<userCount {
            try await chatService.join(userID: "user-\(i)", name: "User \(i)")
        }
        
        let joinDuration = CFAbsoluteTimeGetCurrent() - startTime
        
        // Verify all users joined
        let users = try await chatService.listUsers()
        #expect(users.count == userCount)
        
        // Performance check
        let avgJoinTime = (joinDuration / Double(userCount)) * 1000
        #expect(avgJoinTime < 10, "Average join time should be < 10ms per user")
        
        print("Joined \(userCount) users in \(joinDuration)s (avg: \(avgJoinTime)ms per user)")
    }
    
    @Test("Concurrent message sending")
    func testConcurrentMessageSending() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = ChatServiceActor(actorSystem: serverSystem)
        let chatService = try $Chat.resolve(id: serverActor.id, using: clientSystem)
        
        // Join multiple users
        let userCount = 10
        for i in 0..<userCount {
            try await chatService.join(userID: "user-\(i)", name: "User \(i)")
        }
        
        // Send messages concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<userCount {
                group.addTask {
                    for j in 0..<10 {
                        try await chatService.send("user-\(i)", "Message \(j) from user \(i)")
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify all messages were received
        let history = try await chatService.history()
        #expect(history.count == userCount * 10)
        
        // Verify each user sent 10 messages
        for i in 0..<userCount {
            let userMessages = history.filter { $0.userID == "user-\(i)" }
            #expect(userMessages.count == 10)
        }
    }
    
    // MARK: - Helper Functions
    
    /// Create connected client and server systems
    private func createConnectedSystems() async -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let clientSystem = ActorEdgeSystem(transport: clientTransport)
        let serverSystem = ActorEdgeSystem()
        
        // Set up server transport handler
        Task {
            let stream = serverTransport.receive()
            for await envelope in stream {
                await handleServerEnvelope(envelope, serverSystem: serverSystem, transport: serverTransport)
            }
        }
        
        // Give the server handler task time to start
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        return (clientSystem, serverSystem)
    }
    
    /// Handle server-side envelope processing
    private func handleServerEnvelope(_ envelope: Envelope, serverSystem: ActorEdgeSystem, transport: MessageTransport) async {
        do {
            // Process the invocation
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            var decoder = try processor.createInvocationDecoder(from: envelope, system: serverSystem)
            
            // Find the target actor
            guard let actor = await serverSystem.registry?.find(id: envelope.recipient) else {
                throw ActorEdgeError.actorNotFound(envelope.recipient)
            }
            
            // Create response handler
            let resultHandler = ChatResultHandler(transport: transport, requestEnvelope: envelope)
            
            // Dispatch to actor methods
            if let chatActor = actor as? ChatServiceActor {
                let target = envelope.metadata.target
                
                if target.contains("join") {
                    let userID: String = try decoder.decodeNextArgument()
                    let name: String = try decoder.decodeNextArgument()
                    try await chatActor.join(userID: userID, name: name)
                    try await resultHandler.onReturnVoid()
                } else if target.contains("leave") {
                    let userID: String = try decoder.decodeNextArgument()
                    try await chatActor.leave(userID)
                    try await resultHandler.onReturnVoid()
                } else if target.contains("send") && !target.contains("Message") {
                    let userID: String = try decoder.decodeNextArgument()
                    let text: String = try decoder.decodeNextArgument()
                    try await chatActor.send(userID, text)
                    try await resultHandler.onReturnVoid()
                } else if target.contains("sendMessage") {
                    let message: Message = try decoder.decodeNextArgument()
                    try await chatActor.sendMessage(message)
                    try await resultHandler.onReturnVoid()
                } else if target.contains("listUsers") {
                    let users = try await chatActor.listUsers()
                    try await resultHandler.onReturn(value: users)
                } else if target.contains("history") {
                    let messages = try await chatActor.history()
                    try await resultHandler.onReturn(value: messages)
                } else if target.contains("subscribe") {
                    let userID: String = try decoder.decodeNextArgument()
                    let stream = try await chatActor.subscribe(userID)
                    // For testing, we'll convert the stream to an array
                    let messages = await collectMessages(from: stream, limit: 100)
                    try await resultHandler.onReturn(value: messages)
                } else {
                    throw ActorEdgeError.invocationError("Unknown method: \(target)")
                }
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
    
    /// Create a message collector task
    private func createMessageCollector(stream: AsyncStream<Message>, count: Int) -> Task<[Message], Never> {
        Task {
            var messages: [Message] = []
            for await message in stream {
                messages.append(message)
                if messages.count >= count {
                    break
                }
            }
            return messages
        }
    }
    
    /// Collect messages from a stream
    private func collectMessages(from stream: AsyncStream<Message>, limit: Int) async -> [Message] {
        var messages: [Message] = []
        for await message in stream {
            messages.append(message)
            if messages.count >= limit {
                break
            }
        }
        return messages
    }
}

// MARK: - Result Handler

/// Result handler for chat tests
final class ChatResultHandler: DistributedTargetInvocationResultHandler {
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
        let serializedValue = try serialization.serialize(value)
        let result = InvocationResult.success(serializedValue)
        let resultData = try serialization.serialize(result)
        
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(response)
    }
    
    public func onReturnVoid() async throws {
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