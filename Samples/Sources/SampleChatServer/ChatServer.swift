import ActorEdge
import ActorEdgeServer
import SampleChatShared
import Distributed
import Foundation
import Logging

/// Chat server implementation
public distributed actor ChatServer: Chat {
    public typealias ActorSystem = ActorEdgeSystem
    
    private let logger = Logger(label: "ChatServer")
    
    // Messages storage
    private var messages: [Message] = []
    private var subscribers: [String: AsyncStream<Message>.Continuation] = [:]
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
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
public struct ChatServerMain: Server {
    public init() {}
    
    // MARK: - Actor Configuration
    
    @ActorBuilder
    public func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatServer(actorSystem: actorSystem)
        // PaymentServer(actorSystem: actorSystem)  // Future actors
    }
    
    // MARK: - Server Configuration
    
    public var port: Int { 8000 }
    public var host: String { "127.0.0.1" }
}