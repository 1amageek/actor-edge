import Foundation
import Distributed
import NIO

/// The main serialization runtime for ActorEdge, following Swift Distributed Actors patterns
public struct Serialization: Sendable {
    /// Settings for the serialization runtime
    public let settings: Settings
    
    /// Create a new serialization runtime
    public init() {
        self.settings = Settings()
    }
    
    // MARK: - Main API
    
    /// Serialize a value to a buffer
    public func serialize<T: Codable & Sendable>(_ value: T, system: ActorEdgeSystem? = nil) throws -> Buffer {
        let manifest = try outboundManifest(T.self)
        let serializer = try settings.serializer(for: manifest.serializerID)
        
        let context = Context(
            system: system,
            manifest: manifest
        )
        
        return try serializer.serialize(any: value, context: context)
    }
    
    /// Serialize a value and return both buffer and manifest
    public func serializeWithManifest<T: Codable & Sendable>(_ value: T, system: ActorEdgeSystem? = nil) throws -> (buffer: Buffer, manifest: Manifest) {
        let manifest = try outboundManifest(T.self)
        let buffer = try serialize(value, system: system)
        return (buffer, manifest)
    }
    
    /// Deserialize a buffer to a specific type
    public func deserialize<T: Codable & Sendable>(_ buffer: Buffer, as type: T.Type, system: ActorEdgeSystem? = nil) throws -> T {
        let manifest = try outboundManifest(type)
        let serializer = try settings.serializer(for: manifest.serializerID)
        
        let context = Context(
            system: system,
            manifest: manifest
        )
        
        let any = try serializer.deserialize(buffer: buffer, context: context)
        guard let value = any as? T else {
            throw SerializationError.deserializationFailed("Expected \(T.self), got \(Swift.type(of: any))")
        }
        return value
    }
    
    /// Deserialize using a manifest
    public func deserialize(buffer: Buffer, using manifest: Manifest, system: ActorEdgeSystem? = nil) throws -> Any {
        let serializer = try settings.serializer(for: manifest.serializerID)
        
        // For specialized serializers, system might not be required
        let context = Context(
            system: system,
            manifest: manifest
        )
        
        return try serializer.deserialize(buffer: buffer, context: context)
    }
    
    /// Type-erased deserialization
    public func deserializeErased(
        _ type: any (Codable & Sendable).Type,
        from buffer: Buffer,
        userInfo: [CodingUserInfoKey: Any] = [:],
        system: ActorEdgeSystem? = nil
    ) throws -> Any {
        let manifest = try outboundManifest(type)
        return try deserialize(buffer: buffer, using: manifest, system: system)
    }
    
    /// Get a manifest for a type
    public func outboundManifest(_ type: Any.Type) throws -> Manifest {
        // First check if there's a registered manifest
        if let manifest = settings.manifest(for: type) {
            return manifest
        }
        
        // Check if it's a specialized type
        if settings.hasSpecializedSerializer(for: type) {
            // Include hint for specialized types to support deserialization
            return Manifest(serializerID: .specializedWithTypeHint, hint: Self.getTypeHint(type))
        }
        
        // Default to Codable with type hint
        return Manifest(
            serializerID: settings.defaultSerializerID,
            hint: Self.getTypeHint(type)
        )
    }
    
    /// Get type hint for a type, preferring mangled name for correct deserialization
    @inlinable
    @inline(__always)
    internal static func getTypeHint(_ messageType: Any.Type) -> String {
        // Try mangled name first (required for generic types), fallback to readable name
        _mangledTypeName(messageType) ?? _typeName(messageType)
    }
    
    /// Resolve a type from a manifest
    public func summonType(from manifest: Manifest) throws -> Any.Type {
        // First try to resolve from registered types
        if let type = settings.type(for: manifest) {
            return type
        }
        
        // If no hint, it must be a specialized type
        guard let hint = manifest.hint else {
            throw SerializationError.unknownManifest(manifest)
        }
        
        // Try to resolve the type from hint (could be mangled or demangled)
        if let type = ActorEdge._typeByName(hint) {
            return type
        }
        
        throw SerializationError.unknownManifest(manifest)
    }
    
    // MARK: - Context
    
    /// Context passed to serializers
    public struct Context: Sendable {
        public let system: ActorEdgeSystem?
        public let manifest: Manifest
        
        /// Additional user info for serialization
        public var userInfo: [CodingUserInfoKey: any Sendable] {
            var info: [CodingUserInfoKey: any Sendable] = [:]
            if let system = system {
                info[.actorSystemKey] = system
            }
            return info
        }
    }
}

// MARK: - Type Resolution

/// ActorEdge namespace for shared utilities
public enum ActorEdge {
    /// Resolve a type from its name (mangled or demangled) **without** touching private runtime
    /// symbols. We rely on the public (but SPI‑gated) `Swift._typeByName` helper and fall back to
    /// a small table of common primitives so that reflection remains deterministic even when the
    /// runtime cannot find a match.
    @_spi(Reflection)
    public static func _typeByName(_ name: String) -> Any.Type? {
        // 1. Primary path – standard runtime resolver (handles generics & mangled names).
        if let type = Swift._typeByName(name) {
            return type
        }
        
        // 2. Fallback path – well‑known primitives & Foundation types that appear frequently in
        //    wire manifests. Extend this as needed for domain‑specific models.
        switch name {
        case "Swift.String":                return String.self
        case "Swift.Int":                   return Int.self
        case "Swift.Int32":                 return Int32.self
        case "Swift.Int64":                 return Int64.self
        case "Swift.UInt":                  return UInt.self
        case "Swift.UInt32":                return UInt32.self
        case "Swift.UInt64":                return UInt64.self
        case "Swift.Bool":                  return Bool.self
        case "Swift.Double":                return Double.self
        case "Swift.Float":                 return Float.self
        case "Foundation.Date":             return Date.self
        case "Foundation.Data":             return Data.self
        case "Foundation.URL":              return URL.self
        case "Foundation.UUID":             return UUID.self
        case "ActorEdgeCore.InvocationMessage": return InvocationMessage.self
        default:
            // Generic collections that the runtime fails to reconstruct (rare).
            if name.hasPrefix("Swift.Array<") { return [Any].self }
            if name.hasPrefix("Swift.Dictionary<") { return [String: Any].self }
            return nil
        }
    }
}

// MARK: - Errors

public enum SerializationError: Error, Sendable {
    case serializerNotFound(Serialization.SerializerID)
    case unableToCreateManifest(hint: String?)
    case unknownManifest(Serialization.Manifest)
    case deserializationFailed(String)
}

// MARK: - CodingUserInfoKey Extensions

extension CodingUserInfoKey {
    /// Key for storing the actor system in user info
    public static let actorSystemKey = CodingUserInfoKey(rawValue: "actorSystem")!
}
