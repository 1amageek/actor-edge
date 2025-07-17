import Foundation
import Distributed

/// A unique identifier for distributed actors in the ActorEdge system.
/// 
/// ActorEdgeID supports multiple formats:
/// - Well-known IDs: Simple string identifiers (e.g., "chat-server", "user-service")
/// - Generated IDs: Timestamp-based unique identifiers with optional prefix
/// - Custom IDs: Any string value provided by the user
public struct ActorEdgeID: Sendable, Hashable, Codable {
    private let value: String
    
    /// Creates a new unique actor ID with timestamp and random component
    /// Format: "timestamp-random" where timestamp is Unix epoch in milliseconds
    public init() {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let randomBytes = UUID().uuidString.prefix(8)
        self.value = "\(timestamp)-\(randomBytes)"
    }
    
    /// Creates a new unique actor ID with a prefix
    /// Format: "prefix-timestamp-random"
    public init(prefix: String) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let randomBytes = UUID().uuidString.prefix(8)
        self.value = "\(prefix)-\(timestamp)-\(randomBytes)"
    }
    
    /// Creates an actor ID from an existing string value (well-known ID)
    public init(_ value: String) {
        self.value = value
    }
    
    /// Creates a well-known actor ID (alias for init(_:) for clarity)
    public static func wellKnown(_ id: String) -> ActorEdgeID {
        ActorEdgeID(id)
    }
    
    /// The string representation of this actor ID
    public var description: String {
        value
    }
    
    /// Returns true if this is a well-known ID (doesn't contain timestamp)
    public var isWellKnown: Bool {
        // Simple heuristic: well-known IDs don't contain numbers at the beginning
        !value.contains(where: { $0.isNumber }) || !value.contains("-")
    }
}

// MARK: - CustomStringConvertible
extension ActorEdgeID: CustomStringConvertible {}

// MARK: - Base64URL Encoding
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    init?(base64URLEncoded string: String) {
        let base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        
        self.init(base64Encoded: base64 + padding)
    }
}