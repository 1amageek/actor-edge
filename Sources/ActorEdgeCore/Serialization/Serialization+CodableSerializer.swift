import Foundation

extension Serialization {
    /// JSON serializer using Codable
    public struct CodableSerializer: AnySerializer {
        public let serializerID: SerializerID
        private let encoder: JSONEncoder
        private let decoder: JSONDecoder
        
        public init(serializerID: SerializerID = .json) {
            self.serializerID = serializerID
            
            // Configure encoder with ActorEdge defaults
            self.encoder = JSONEncoder()
            self.encoder.dateEncodingStrategy = .iso8601
            self.encoder.dataEncodingStrategy = .base64
            
            // Configure decoder with ActorEdge defaults
            self.decoder = JSONDecoder()
            self.decoder.dateDecodingStrategy = .iso8601
            self.decoder.dataDecodingStrategy = .base64
        }
        
        public func serialize(any value: Any, context: Context) throws -> Buffer {
            // Set up encoder user info
            encoder.userInfo = context.userInfo
            
            // Get the actual type from the manifest if available
            let valueType = context.manifest.hint.flatMap(ActorEdge._typeByName) ?? type(of: value)
            
            // Serialize based on type
            guard let codableType = valueType as? any (Codable & Sendable).Type else {
                throw SerializationError.deserializationFailed(
                    "Type \(valueType) does not conform to Codable & Sendable"
                )
            }
            
            // Type-erased encoding
            let data = try encodeErased(value, as: codableType)
            return .data(data)
        }
        
        public func deserialize(buffer: Buffer, context: Context) throws -> Any {
            // Set up decoder user info
            decoder.userInfo = context.userInfo
            
            let data = buffer.readData()
            
            // Get the type from manifest if available
            if let hint = context.manifest.hint,
               let targetType = ActorEdge._typeByName(hint),
               let codableType = targetType as? any (Codable & Sendable).Type {
                // We know the exact type, decode directly
                return try decoder.decode(codableType, from: data)
            }
            
            // For unknown types with hints, return the raw JSON data
            // The caller (like InvocationDecoder) will handle type conversion
            if context.manifest.hint != nil {
                // Try to decode as a generic JSON structure
                if let jsonObject = try? JSONSerialization.jsonObject(with: data),
                   JSONSerialization.isValidJSONObject(jsonObject) {
                    // Return the data itself - the decoder will handle conversion
                    return data
                }
            }
            
            // No hint or can't decode - this is an error
            throw SerializationError.unknownManifest(context.manifest)
        }
        
        // MARK: - Private Helpers
        
        private func encodeErased(_ value: Any, as type: any (Codable & Sendable).Type) throws -> Data {
            // This is a workaround for type-erased encoding
            // Try to encode directly if the value is already Codable
            
            // Helper to encode specific types
            func tryEncode<T: Codable>(_ type: T.Type) throws -> Data? {
                guard let typedValue = value as? T else { return nil }
                return try encoder.encode(typedValue)
            }
            
            // Try common types first for better performance
            if let data = try tryEncode(String.self) { return data }
            if let data = try tryEncode(Int.self) { return data }
            if let data = try tryEncode(Bool.self) { return data }
            if let data = try tryEncode(Double.self) { return data }
            if let data = try tryEncode(Date.self) { return data }
            if let data = try tryEncode(Data.self) { return data }
            
            // Fallback to AnyEncodable wrapper
            let anyEncodable = AnyEncodable(value: value)
            return try encoder.encode(anyEncodable)
        }
    }
}

// MARK: - Foundation JSON Serializer

extension Serialization {
    /// Foundation JSON serializer (same as CodableSerializer but with different ID)
    public struct FoundationJSONSerializer: AnySerializer {
        private let codableSerializer: CodableSerializer
        
        public var serializerID: SerializerID { .foundationJSON }
        
        public init() {
            self.codableSerializer = CodableSerializer(serializerID: .foundationJSON)
        }
        
        public func serialize(any value: Any, context: Context) throws -> Buffer {
            try codableSerializer.serialize(any: value, context: context)
        }
        
        public func deserialize(buffer: Buffer, context: Context) throws -> Any {
            try codableSerializer.deserialize(buffer: buffer, context: context)
        }
    }
}

// MARK: - Helper Types

/// A type-erased encodable wrapper
private struct AnyEncodable: Encodable {
    let value: Any
    
    func encode(to encoder: Encoder) throws {
        // First check if the value is already Encodable
        if let encodable = value as? any Encodable {
            // Use a helper function to encode the type-erased value
            try encodable.encodeErased(to: encoder)
            return
        }
        
        var container = encoder.singleValueContainer()
        
        switch value {
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Int8:
            try container.encode(v)
        case let v as Int16:
            try container.encode(v)
        case let v as Int32:
            try container.encode(v)
        case let v as Int64:
            try container.encode(v)
        case let v as UInt:
            try container.encode(v)
        case let v as UInt8:
            try container.encode(v)
        case let v as UInt16:
            try container.encode(v)
        case let v as UInt32:
            try container.encode(v)
        case let v as UInt64:
            try container.encode(v)
        case let v as Float:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as Date:
            try container.encode(v)
        case let v as Data:
            try container.encode(v)
        case let v as URL:
            try container.encode(v)
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyEncodable(value: $0) })
        case let v as [Any]:
            try container.encode(v.map { AnyEncodable(value: $0) })
        default:
            let context = EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "Cannot encode value of type \(type(of: value))"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

// Extension to handle type-erased encoding
private extension Encodable {
    func encodeErased(to encoder: Encoder) throws {
        try self.encode(to: encoder)
    }
}