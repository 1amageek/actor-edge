import Foundation

extension Serialization {
    /// Protocol for all serializers in the system
    public protocol AnySerializer: Sendable {
        /// The unique identifier for this serializer
        var serializerID: SerializerID { get }
        
        /// Serialize any value to a buffer
        func serialize(any value: Any, context: Context) throws -> Buffer
        
        /// Deserialize a buffer to any value
        func deserialize(buffer: Buffer, context: Context) throws -> Any
    }
}

// MARK: - Type-Safe Wrapper

extension Serialization {
    /// A type-safe wrapper around AnySerializer for specific types
    public struct TypedSerializer<T: Codable & Sendable>: AnySerializer {
        public let serializerID: SerializerID
        private let _serialize: @Sendable (T, Context) throws -> Buffer
        private let _deserialize: @Sendable (Buffer, Context) throws -> T
        
        public init(
            serializerID: SerializerID,
            serialize: @escaping @Sendable (T, Context) throws -> Buffer,
            deserialize: @escaping @Sendable (Buffer, Context) throws -> T
        ) {
            self.serializerID = serializerID
            self._serialize = serialize
            self._deserialize = deserialize
        }
        
        public func serialize(any value: Any, context: Context) throws -> Buffer {
            guard let typedValue = value as? T else {
                throw SerializationError.deserializationFailed(
                    "Expected \(T.self), got \(type(of: value))"
                )
            }
            return try _serialize(typedValue, context)
        }
        
        public func deserialize(buffer: Buffer, context: Context) throws -> Any {
            return try _deserialize(buffer, context)
        }
    }
}

// MARK: - Helper Extensions

extension Serialization.AnySerializer {
    /// Check if this serializer requires a type hint
    public var requiresTypeHint: Bool {
        switch serializerID {
        case .specializedWithTypeHint:
            return false
        default:
            return true
        }
    }
    
    /// Get a human-readable name for this serializer
    public var name: String {
        serializerID.description
    }
}