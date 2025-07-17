import ActorEdge
import ActorEdgeClient
import SampleChatShared
import Distributed
import Foundation

@main
struct ChatClient {
    static func main() async throws {
        // Connect to the server
        let transport = try await GRPCActorTransport("127.0.0.1:8000")
        let system = ActorEdgeSystem(transport: transport)
        
        // Get the chat actor with the well-known ID
        let chat = try $Chat.resolve(id: ActorEdgeID.wellKnown("chat-server"), using: system)
        
        // Send a message
        let message = Message(username: "Alice", content: "Hello from ActorEdge!")
        try await chat.send(message)
        print("✅ Message sent!")
        
        // Get recent messages
        let messages = try await chat.getRecentMessages(limit: 5)
        print("\n📨 Recent messages:")
        for msg in messages {
            print("  [\(msg.username)]: \(msg.content)")
        }
    }
}