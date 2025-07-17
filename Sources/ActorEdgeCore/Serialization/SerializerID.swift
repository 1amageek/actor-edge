import Foundation

/// Identifies the serialization format
/// Based on swift-distributed-actors SerializerID
public enum SerializerID: UInt32, Codable, Sendable, CaseIterable {
    /// JSON serialization (matches swift-distributed-actors' foundationJSON)
    case json = 3
    
    // Future serialization formats:
    // case protobuf = 2
    // case propertyListBinary = 4
    // case custom = 100
}

// MARK: - CustomStringConvertible
extension SerializerID: CustomStringConvertible {
    public var description: String {
        switch self {
        case .json:
            return "json"
        }
    }
}

// MARK: - Serializer Properties
extension SerializerID {
    /// Human-readable name for the serializer
    public var name: String {
        switch self {
        case .json:
            return "JSON"
        }
    }
    
    /// Whether this serializer supports pretty printing
    public var supportsPrettyPrinting: Bool {
        switch self {
        case .json:
            return true
        }
    }
    
    /// Default serializer to use when none is specified
    public static var `default`: SerializerID {
        return .json
    }
}