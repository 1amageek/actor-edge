import Testing
import SampleChatShared
import SampleChatServer
@testable import ActorEdgeCore
import ActorEdgeServer
import Distributed

@Suite("Chat Sample Application Tests", .tags(.sample, .integration))
struct ChatApplicationTests {
    
    @Test("Chat message flow")
    func chatMessageFlow() async throws {
        // Force type retention for Message
        Message._forceTypeRetention()
        
        // Create server
        let serverSystem = ActorEdgeSystem(metricsNamespace: "chat_server")
        serverSystem.setPreAssignedIDs(["chat-server"])
        
        let chatActor = ChatActor(actorSystem: serverSystem)
        
        // Create client connection
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        let clientSystem = ActorEdgeSystem(transport: clientTransport, metricsNamespace: "chat_client")
        
        // Set up server transport to handle chat messages
        serverTransport.setMessageHandler { envelope in
            // For testing, just echo back
            if envelope.messageType == .invocation {
                return Envelope.response(
                    to: envelope.sender ?? envelope.recipient,
                    callID: envelope.metadata.callID,
                    manifest: envelope.manifest,
                    payload: envelope.payload
                )
            }
            return nil
        }
        
        // Resolve chat actor from client
        let remoteChat = try $Chat.resolve(id: chatActor.id, using: clientSystem)
        
        // Send messages
        let message1 = Message(username: "Alice", content: "Hello!")
        let message2 = Message(username: "Bob", content: "Hi Alice!")
        
        try await remoteChat.send(message1)
        try await remoteChat.send(message2)
        
        // Retrieve messages
        let messages = try await remoteChat.getRecentMessages(limit: 10)
        
        #expect(messages.count == 2)
        #expect(messages[0].username == "Alice")
        #expect(messages[0].content == "Hello!")
        #expect(messages[1].username == "Bob")
        #expect(messages[1].content == "Hi Alice!")
    }
    
    @Test("Message timestamps are preserved")
    func messageTimestamps() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        let beforeTime = Date()
        let message = Message(username: "Test", content: "Test message")
        try await chatActor.send(message)
        let afterTime = Date()
        
        let messages = try await chatActor.getRecentMessages(limit: 1)
        #expect(messages.count == 1)
        
        let retrievedMessage = messages[0]
        #expect(retrievedMessage.timestamp >= beforeTime)
        #expect(retrievedMessage.timestamp <= afterTime)
    }
    
    @Test("Message limit enforcement")
    func messageLimitEnforcement() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        // Send more than 100 messages (the limit in ChatActor)
        for i in 1...110 {
            let message = Message(username: "User", content: "Message \(i)")
            try await chatActor.send(message)
        }
        
        // Should only return the last 100 messages
        let allMessages = try await chatActor.getRecentMessages(limit: 200)
        #expect(allMessages.count == 100)
        
        // The first message should be "Message 11" (messages 1-10 should be dropped)
        #expect(allMessages.first?.content == "Message 11")
        #expect(allMessages.last?.content == "Message 110")
    }
    
    @Test("Get messages since timestamp")
    func getMessagesSinceTimestamp() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        // Send initial messages
        let message1 = Message(username: "User1", content: "First message")
        try await chatActor.send(message1)
        
        let timestampBetween = Date()
        try await Task.sleep(for: .milliseconds(10)) // Ensure timestamp difference
        
        let message2 = Message(username: "User2", content: "Second message")
        try await chatActor.send(message2)
        
        // Get messages since the timestamp between the two messages
        let recentMessages = try await chatActor.getMessagesSince(timestampBetween, username: "TestUser")
        
        #expect(recentMessages.count == 1)
        #expect(recentMessages[0].content == "Second message")
    }
    
    @Test("Multiple users chatting")
    func multipleUsersChatting() async throws {
        // Force type retention
        Message._forceTypeRetention()
        
        // Create server
        let serverSystem = ActorEdgeSystem(metricsNamespace: "multi_user_chat")
        serverSystem.setPreAssignedIDs(["chat-room"])
        
        let chatActor = ChatActor(actorSystem: serverSystem)
        
        // Create multiple client connections
        let (clientTransport1, serverTransport1) = InMemoryMessageTransport.createConnectedPair()
        let (clientTransport2, serverTransport2) = InMemoryMessageTransport.createConnectedPair()
        
        let clientSystem1 = ActorEdgeSystem(transport: clientTransport1, metricsNamespace: "client1")
        let clientSystem2 = ActorEdgeSystem(transport: clientTransport2, metricsNamespace: "client2")
        
        // Set up server transports
        for transport in [serverTransport1, serverTransport2] {
            transport.setMessageHandler { envelope in
                if envelope.messageType == .invocation {
                    return Envelope.response(
                        to: envelope.sender ?? envelope.recipient,
                        callID: envelope.metadata.callID,
                        manifest: envelope.manifest,
                        payload: envelope.payload
                    )
                }
                return nil
            }
        }
        
        // Both clients resolve the same chat actor
        let remoteChat1 = try $Chat.resolve(id: chatActor.id, using: clientSystem1)
        let remoteChat2 = try $Chat.resolve(id: chatActor.id, using: clientSystem2)
        
        // Simulate conversation
        try await remoteChat1.send(Message(username: "Alice", content: "Anyone here?"))
        try await remoteChat2.send(Message(username: "Bob", content: "Yes, I'm here!"))
        try await remoteChat1.send(Message(username: "Alice", content: "Great! How are you?"))
        try await remoteChat2.send(Message(username: "Bob", content: "Doing well, thanks!"))
        
        // Both users should see all messages
        let messages1 = try await remoteChat1.getRecentMessages(limit: 10)
        let messages2 = try await remoteChat2.getRecentMessages(limit: 10)
        
        #expect(messages1.count == 4)
        #expect(messages2.count == 4)
        
        // Verify message order is consistent
        for (msg1, msg2) in zip(messages1, messages2) {
            #expect(msg1.id == msg2.id)
            #expect(msg1.username == msg2.username)
            #expect(msg1.content == msg2.content)
        }
    }
    
    @Test("Empty chat room")
    func emptyChatRoom() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        // Get messages from empty chat
        let messages = try await chatActor.getRecentMessages(limit: 10)
        #expect(messages.isEmpty)
        
        // Get messages since timestamp from empty chat
        let messagesSince = try await chatActor.getMessagesSince(Date(), username: "Test")
        #expect(messagesSince.isEmpty)
    }
    
    @Test("Message IDs are unique")
    func messageIDsAreUnique() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        // Send multiple messages
        let messageCount = 20
        for i in 1...messageCount {
            let message = Message(username: "User", content: "Message \(i)")
            try await chatActor.send(message)
        }
        
        // Get all messages
        let messages = try await chatActor.getRecentMessages(limit: messageCount)
        
        // Check that all IDs are unique
        let messageIDs = messages.map { $0.id }
        let uniqueIDs = Set(messageIDs)
        
        #expect(messageIDs.count == uniqueIDs.count)
        #expect(uniqueIDs.count == messageCount)
    }
    
    @Test("Special characters in messages")
    func specialCharactersInMessages() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        // Messages with special characters
        let specialMessages = [
            Message(username: "User😀", content: "Hello with emoji! 🎉🎊"),
            Message(username: "User", content: "Unicode: こんにちは 你好 مرحبا"),
            Message(username: "User<script>", content: "HTML: <b>bold</b> & \"quoted\""),
            Message(username: "User\n\t", content: "Newline\nand\ttabs"),
            Message(username: "User", content: String(repeating: "🔥", count: 100))
        ]
        
        // Send all special messages
        for message in specialMessages {
            try await chatActor.send(message)
        }
        
        // Retrieve and verify
        let retrieved = try await chatActor.getRecentMessages(limit: specialMessages.count)
        #expect(retrieved.count == specialMessages.count)
        
        // Verify content is preserved exactly
        for (sent, received) in zip(specialMessages, retrieved) {
            #expect(sent.username == received.username)
            #expect(sent.content == received.content)
        }
    }
    
    @Test("Concurrent message sending")
    func concurrentMessageSending() async throws {
        let system = ActorEdgeSystem()
        let chatActor = ChatActor(actorSystem: system)
        
        let messageCount = 50
        
        // Send messages concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...messageCount {
                group.addTask {
                    let message = Message(username: "User\(i % 5)", content: "Concurrent message \(i)")
                    try? await chatActor.send(message)
                }
            }
        }
        
        // All messages should be received
        let messages = try await chatActor.getRecentMessages(limit: messageCount)
        #expect(messages.count == messageCount)
        
        // Verify all messages are present (order may vary due to concurrency)
        let contents = Set(messages.map { $0.content })
        #expect(contents.count == messageCount)
    }
}