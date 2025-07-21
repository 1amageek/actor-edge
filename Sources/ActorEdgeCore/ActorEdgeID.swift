import Foundation
import Distributed

/// Identifies a distributed actor in the ActorEdge system.
///
/// Simplified version for edge computing without cluster concepts.
/// Supports both fixed string IDs (e.g., "chat-server") and generated IDs.
public struct ActorEdgeID: Sendable, Hashable, Codable {
    /// The actor identifier value
    public let value: String
    
    /// Optional metadata for future extensibility
    public let metadata: [String: String]
    
    /// Creates a new random ActorEdgeID.
    public init() {
        // Generate short UUID (8 characters)
        self.value = UUID().uuidString.prefix(8).lowercased()
        self.metadata = [:]
    }
    
    /// Creates an ActorEdgeID from a string value.
    public init(_ value: String, metadata: [String: String] = [:]) {
        self.value = value
        self.metadata = metadata
    }
    
    /// The string representation of this ID.
    public var description: String {
        value
    }
}

// MARK: - CustomStringConvertible
extension ActorEdgeID: CustomStringConvertible {}

// MARK: - ExpressibleByStringLiteral
extension ActorEdgeID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}