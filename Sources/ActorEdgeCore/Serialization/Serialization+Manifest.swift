import Foundation

extension Serialization {
    /// Manifest describing how a value was serialized
    public struct Manifest: Codable, Sendable, Hashable {
        /// The serializer used
        public let serializerID: SerializerID
        
        /// Optional hint for type resolution (e.g., String(reflecting: type))
        public let hint: String?
        
        public init(serializerID: SerializerID, hint: String? = nil) {
            self.serializerID = serializerID
            self.hint = hint
        }
    }
}

// MARK: - Convenience Initializers

extension Serialization.Manifest {
    /// Create a manifest for a JSON-serialized Codable type
    public static func json<T>(for type: T.Type) -> Serialization.Manifest {
        Serialization.Manifest(
            serializerID: .json,
            hint: String(reflecting: type)
        )
    }
    
    /// Create a manifest for Foundation JSON
    public static func foundationJSON<T>(for type: T.Type) -> Serialization.Manifest {
        Serialization.Manifest(
            serializerID: .foundationJSON,
            hint: String(reflecting: type)
        )
    }
    
    /// Create a manifest for a specialized type (no hint needed)
    public static func specialized() -> Serialization.Manifest {
        Serialization.Manifest(
            serializerID: .specializedWithTypeHint,
            hint: nil
        )
    }
    
    /// Create a manifest for a custom serializer
    public static func custom<T>(_ id: Int, for type: T.Type) -> Serialization.Manifest {
        Serialization.Manifest(
            serializerID: .custom(id),
            hint: String(reflecting: type)
        )
    }
}

// MARK: - CustomStringConvertible

extension Serialization.Manifest: CustomStringConvertible {
    public var description: String {
        if let hint = hint {
            return "Manifest(\(serializerID), hint: \(hint))"
        } else {
            return "Manifest(\(serializerID))"
        }
    }
}

// MARK: - Compatibility

extension Serialization.Manifest {
    /// Check if this manifest can be handled by the current runtime
    public var isSupported: Bool {
        switch serializerID {
        case .json, .foundationJSON, .specializedWithTypeHint:
            return true
        case .foundationPropertyListBinary, .foundationPropertyListXML:
            return false // Not implemented yet
        case .custom(_):
            return true // Assume custom serializers are registered
        }
    }
    
    /// Get a human-readable name for the serializer
    public var serializerName: String {
        switch serializerID {
        case .json:
            return "JSON"
        case .foundationJSON:
            return "Foundation JSON"
        case .foundationPropertyListBinary:
            return "Property List (Binary)"
        case .foundationPropertyListXML:
            return "Property List (XML)"
        case .specializedWithTypeHint:
            return "Specialized"
        case .custom(let id):
            return "Custom(\(id))"
        }
    }
}