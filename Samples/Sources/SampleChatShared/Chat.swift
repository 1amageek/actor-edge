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
        
        // Force type retention first
        Message._forceTypeRetention()
        
        print("Message type: \(String(reflecting: Message.self))")
        
        // Check mangled name
        if let mangledName = _mangledTypeName(Message.self) {
            print("Mangled name: \(mangledName)")
        } else {
            print("Mangled name: Not available")
        }
        
        // Test multiple type resolution patterns
        let typeName = String(reflecting: Message.self)
        print("\n🔍 [DIAGNOSTIC] Testing type resolution patterns:")
        
        // Pattern 1: Direct type name
        if let resolved = _typeByName(typeName) {
            print("✅ Direct resolution successful: \(resolved)")
        } else {
            print("❌ Direct resolution failed for: \(typeName)")
        }
        
        // Pattern 2: Try NSClassFromString
        if let resolved = NSClassFromString(typeName) {
            print("✅ NSClassFromString successful: \(resolved)")
        } else {
            print("❌ NSClassFromString failed for: \(typeName)")
        }
        
        // Pattern 3: Try variations
        let variations = [
            "Message",
            "SampleChatShared.Message",
            "SampleChatShared_Message",
            "16SampleChatShared7MessageV"
        ]
        
        for variation in variations {
            if let resolved = _typeByName(variation) {
                print("✅ Variation '\(variation)' resolved: \(resolved)")
            } else {
                print("❌ Variation '\(variation)' failed")
            }
        }
        
        print("==================================\n")
    }
}
