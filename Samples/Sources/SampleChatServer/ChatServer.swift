import ActorEdge
import ActorEdgeServer
import SampleChatShared
import Distributed
import Foundation
import Logging

/// Chat server implementation
public distributed actor ChatActor: Chat {
    public typealias ActorSystem = ActorEdgeSystem
    
    private let logger = Logger(label: "ChatServer")
    
    // Messages storage
    private var messages: [Message] = []
    private var subscribers: [String: AsyncStream<Message>.Continuation] = [:]
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
        let actorID = self.id
        Task {
            // Print the actor ID for clients to use
            try await Task.sleep(nanoseconds: 100_000_000) // Small delay to ensure ID is assigned
            Logger(label: "ChatServer").info("ChatActor initialized with ID: \(actorID)")
        }
    }
    
    // MARK: - Chat Implementation
    
    public distributed func send(_ message: Message) async throws {
        logger.info("Received message from \\(message.username): \\(message.content)")
        
        // Store the message
        messages.append(message)
        
        // Keep only last 100 messages
        if messages.count > 100 {
            messages.removeFirst()
        }
        
        // Notify all subscribers
        for continuation in subscribers.values {
            continuation.yield(message)
        }
    }
    
    public distributed func getRecentMessages(limit: Int) async throws -> [Message] {
        let recentMessages = Array(messages.suffix(limit))
        logger.info("Sending \\(recentMessages.count) recent messages")
        return recentMessages
    }
    
    public distributed func getMessagesSince(_ timestamp: Date, username: String) async throws -> [Message] {
        let filteredMessages = messages.filter { $0.timestamp > timestamp }
        logger.info("Sending \\(filteredMessages.count) messages since \\(timestamp) for \\(username)")
        return filteredMessages
    }
}

// MARK: - Server Main

@main
struct ChatServer: Server {
    
    var port: Int { 8000 }
    
    var host: String { "127.0.0.1" }
    
    // Provide well-known IDs for our actors
    var actorIDs: [String] { ["chat-server"] }
  
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        // Debug type resolution
        ChatDebug.printTypeInfo()
        
        return [ChatActor(actorSystem: actorSystem)]
    }
}
