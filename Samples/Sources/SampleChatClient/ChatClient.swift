import ActorEdge
import ActorEdgeClient
import SampleChatShared
import Distributed
import Foundation

/// Simple chat client implementation
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
@main
struct ChatClient {
    static func main() async throws {
        // Create transport and actor system
        let transport = try await GRPCActorTransport("127.0.0.1:8000")
        let system = ActorEdgeSystem(transport: transport)
        
        // Resolve the chat actor
        let chat = try $Chat.resolve(id: ActorEdgeID(), using: system)
        
        // Get username from command line or use default
        let username = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TestUser"
        
        // Send a message
        let message = Message(username: username, content: "Hello from ActorEdge!")
        try await chat.send(message)
        
        print("Message sent successfully!")
        
        // Get recent messages to verify
        let recentMessages = try await chat.getRecentMessages(limit: 5)
        if !recentMessages.isEmpty {
            print("\nRecent messages:")
            for message in recentMessages {
                print("  \(message.username): \(message.content)")
            }
        }
    }
}