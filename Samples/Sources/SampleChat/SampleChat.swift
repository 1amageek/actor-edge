import ActorEdge
import SampleChatShared
import Distributed
import Foundation
import Logging

/// Combined chat sample that demonstrates both server and client functionality
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
@main
struct SampleChat {
    static func main() async throws {
        LoggingSystem.bootstrap(StreamLogHandler.standardOutput)
        let logger = Logger(label: "SampleChat")
        
        logger.info("Starting ActorEdge Chat Sample")
        logger.info("This sample demonstrates a simple chat system using ActorEdge")
        
        // Start server in background
        logger.info("Starting chat server...")
        let serverTask = Task {
            // Create actor system
            let system = ActorEdgeSystem()
            
            // Create the chat actor
            let chatActor = ChatServer(actorSystem: system)
            
            // Start a simple server
            struct SimpleServer: Server {
                var port: Int { 8000 }
                var host: String { "127.0.0.1" }
            }
            
            try await SimpleServer.main()
        }
        
        // Wait a bit for server to start
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Create transport and actor system for client
        let transport = try await GRPCActorTransport("127.0.0.1:8000")
        let system = ActorEdgeSystem(transport: transport)
        
        // Resolve the chat actor
        let chat = try $Chat.resolve(id: ActorEdgeID(), using: system)
        
        logger.info("Connected to chat server")
        
        // Send some sample messages
        let messages = [
            Message(username: "Alice", content: "Hello everyone!"),
            Message(username: "Bob", content: "Hey Alice! How's it going?"),
            Message(username: "Charlie", content: "Great to see you all here!"),
            Message(username: "Alice", content: "This ActorEdge framework is pretty cool!"),
            Message(username: "Bob", content: "Yeah, distributed actors are awesome!")
        ]
        
        for message in messages {
            try await chat.send(message)
            logger.info("Sent message from \\(message.username): \\(message.content)")
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Get recent messages
        let recentMessages = try await chat.getRecentMessages(limit: 10)
        
        logger.info("Recent messages from server:")
        for message in recentMessages {
            print("[\\(formatDate(message.timestamp))] \\(message.username): \\(message.content)")
        }
        
        logger.info("Sample completed successfully!")
        
        // Cancel server task
        serverTask.cancel()
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// In-memory chat server for the sample
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
distributed actor ChatServer: Chat {
    public typealias ActorSystem = ActorEdgeSystem
    
    private var messages: [Message] = []
    private var subscribers: [String: AsyncStream<Message>.Continuation] = [:]
    
    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    // MARK: - Chat Implementation
    
    distributed func send(_ message: Message) async throws {
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
    
    distributed func getRecentMessages(limit: Int) async throws -> [Message] {
        return Array(messages.suffix(limit))
    }
    
    distributed func getMessagesSince(_ timestamp: Date, username: String) async throws -> [Message] {
        let filteredMessages = messages.filter { $0.timestamp > timestamp }
        return filteredMessages
    }
}