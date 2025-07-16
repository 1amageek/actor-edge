import ActorEdge
import Distributed
import Foundation

/// Message structure for chat
public struct Message: Codable, Sendable {
    public let id: String
    public let username: String
    public let content: String
    public let timestamp: Date
    
    public init(id: String = UUID().uuidString, username: String, content: String, timestamp: Date = Date()) {
        self.id = id
        self.username = username
        self.content = content
        self.timestamp = timestamp
    }
}

/// Chat protocol using @Resolvable for distributed actors
@Resolvable
public protocol Chat: DistributedActor where ActorSystem == ActorEdgeSystem {
    /// Send a message to the chat
    distributed func send(_ message: Message) async throws
    
    /// Get recent messages
    distributed func getRecentMessages(limit: Int) async throws -> [Message]
    
    /// Get new messages since a specific timestamp
    distributed func getMessagesSince(_ timestamp: Date, username: String) async throws -> [Message]
}