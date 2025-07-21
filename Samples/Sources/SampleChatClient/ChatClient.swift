import ActorEdge
import ActorEdgeClient
import SampleChatShared
import Distributed
import Foundation

/// Simple chat client
@main
struct ChatClient {
    static func main() async throws {
        // Debug type resolution
        ChatDebug.printTypeInfo()
        
        // Connect to server
        let system = try await ActorEdgeSystem.grpcClient(endpoint: "127.0.0.1:8000")
        
        // Resolve chat actor
        let chat = try $Chat.resolve(id: ActorEdgeID("chat-server"), using: system)
        
        // Send a test message
        let message = Message(
            username: "TestUser",
            content: "Hello from client!"
        )
        
        try await chat.send(message)
        print("Message sent successfully!")
        
        // Get recent messages
        let messages = try await chat.getRecentMessages(limit: 5)
        print("\nRecent messages:")
        for msg in messages {
            print("- \(msg.username): \(msg.content)")
        }
    }
}