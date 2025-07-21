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
    
    /// Force the type to be retained in the binary for runtime type resolution
    @_optimize(none)
    public static func _forceTypeRetention() {
        _ = Message.self
        _ = String(reflecting: Message.self)
        print("Message type retained in binary: \(String(reflecting: Message.self))")
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

// Debug helper for type resolution
public enum ChatDebug {
    public static func printTypeInfo() {
        print("\n=== Type Resolution Debug Info ===")
        
        // 型保持を強制
        Message._forceTypeRetention()
        
        print("Message type: \(String(reflecting: Message.self))")
        
        // Mangled nameのテスト
        if let mangledName = _mangledTypeName(Message.self) {
            print("Mangled name: \(mangledName)")
            
            // 実際に解決できるかテスト
            if let resolved = _typeByName(mangledName) {
                print("✅ Mangled name resolved: \(resolved)")
            } else {
                print("❌ Mangled name resolution failed")
            }
        } else {
            print("❌ No mangled name available")
        }
        
        print("==================================\n")
    }
}
