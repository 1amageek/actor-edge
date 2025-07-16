import Foundation
import Distributed

/// A unique identifier for distributed actors in the ActorEdge system.
/// Uses a 96-bit UUID encoded as base64url for compact representation.
public struct ActorEdgeID: Sendable, Hashable, Codable {
    private let value: String
    
    /// Creates a new unique actor ID
    public init() {
        let uuid = UUID()
        let data = withUnsafeBytes(of: uuid) { Data($0) }
        self.value = data.base64URLEncodedString()
    }
    
    /// Creates an actor ID from an existing string value
    public init(_ value: String) {
        self.value = value
    }
    
    /// The string representation of this actor ID
    public var description: String {
        value
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