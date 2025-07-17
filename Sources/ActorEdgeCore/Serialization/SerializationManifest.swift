import Foundation

/// Carries type information necessary for deserialization
/// Based on swift-distributed-actors Serialization.Manifest
public struct SerializationManifest: Codable, Sendable, Hashable {
    /// Identifies which serializer to use
    public let serializerID: SerializerID
    
    /// Type name for deserialization
    /// In swift-distributed-actors this is called 'hint' and uses mangled type names
    /// We use explicit type names for clarity and debugging
    public let typeName: String
    
    public init(serializerID: SerializerID, typeName: String) {
        precondition(!typeName.isEmpty, "Manifest.typeName MUST NOT be empty")
        self.serializerID = serializerID
        self.typeName = typeName
    }
}

// MARK: - CustomStringConvertible
extension SerializationManifest: CustomStringConvertible {
    public var description: String {
        "SerializationManifest(\(serializerID), type: \(typeName))"
    }
}

// MARK: - Convenience Initializers
extension SerializationManifest {
    /// Create a manifest for a Codable type using JSON serialization
    public static func json<T>(for type: T.Type) -> SerializationManifest {
        SerializationManifest(
            serializerID: .json,
            typeName: String(reflecting: type)
        )
    }
    
    /// Create a manifest from a type using the default serializer
    public static func `default`<T>(for type: T.Type) -> SerializationManifest {
        // Default to JSON for now
        json(for: type)
    }
}