import Foundation
import Distributed
import Logging

/// The main serialization engine for ActorEdge
/// Based on swift-distributed-actors Serialization system
public final class ActorEdgeSerialization: @unchecked Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private weak var system: ActorEdgeSystem?
    private let logger: Logger
    
    /// Initialize the serialization system
    public init() {
        self.logger = Logger(label: "ActorEdge.Serialization")
        
        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
            self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        } else {
            self.encoder.outputFormatting = .sortedKeys
        }
        
        // Configure JSON decoder
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    /// Set the actor system (called after initialization)
    internal func setSystem(_ system: ActorEdgeSystem) {
        self.system = system
    }
    
    // MARK: - Core Serialization Methods
    
    /// Serialize a value into a buffer
    public func serialize<T>(_ value: T) throws -> SerializationBuffer where T: Codable & Sendable {
        logger.trace("Serializing value of type \(String(reflecting: T.self))")
        
        do {
            let data = try encoder.encode(value)
            return .data(data)
        } catch {
            logger.error("Serialization failed", metadata: [
                "type": "\(T.self)",
                "error": "\(error)"
            ])
            throw ActorEdgeError.serializationFailed("Failed to serialize \(T.self): \(error)")
        }
    }
    
    /// Deserialize a value from a buffer
    public func deserialize<T>(
        _ type: T.Type,
        from buffer: SerializationBuffer,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T where T: Codable & Sendable {
        logger.trace("Deserializing type \(String(reflecting: type))")
        
        // Set up decoder with user info
        var combinedUserInfo = userInfo
        
        // Critical: Add actor system to userInfo for distributed actor deserialization
        if combinedUserInfo[.actorSystemKey] == nil {
            combinedUserInfo[.actorSystemKey] = system
        }
        
        decoder.userInfo = combinedUserInfo
        
        do {
            let data = buffer.readData()
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Deserialization failed", metadata: [
                "type": "\(type)",
                "error": "\(error)"
            ])
            throw ActorEdgeError.deserializationFailed("Failed to deserialize \(type): \(error)")
        }
    }
    
    /// Create a manifest for a given type
    public func outboundManifest(_ type: Any.Type) -> SerializationManifest {
        let typeName = TypeResolver.typeName(for: type)
        logger.trace("Creating manifest for type \(typeName)")
        
        return SerializationManifest(
            serializerID: .json,
            typeName: typeName
        )
    }
    
    /// Resolve a type from a manifest
    public func summonType(from manifest: SerializationManifest) throws -> Any.Type {
        logger.trace("Summoning type from manifest", metadata: [
            "serializerID": "\(manifest.serializerID)",
            "typeName": "\(manifest.typeName)"
        ])
        
        guard manifest.serializerID == .json else {
            throw ActorEdgeError.serializationFailed(
                "Unsupported serializer: \(manifest.serializerID)"
            )
        }
        
        guard let type = TypeResolver.resolveType(from: manifest.typeName) else {
            logger.error("Failed to resolve type", metadata: [
                "typeName": "\(manifest.typeName)"
            ])
            throw ActorEdgeError.serializationFailed(
                "Cannot resolve type: \(manifest.typeName)"
            )
        }
        
        return type
    }
    
    // MARK: - Convenience Methods
    
    /// Serialize with manifest
    public func serializeWithManifest<T>(
        _ value: T
    ) throws -> (buffer: SerializationBuffer, manifest: SerializationManifest) where T: Codable & Sendable {
        let buffer = try serialize(value)
        let manifest = outboundManifest(T.self)
        return (buffer, manifest)
    }
    
    /// Deserialize using manifest
    public func deserializeWithManifest(
        from buffer: SerializationBuffer,
        manifest: SerializationManifest,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> Any {
        let type = try summonType(from: manifest)
        
        // We need to use type-erased deserialization here
        // This is a limitation of Swift's type system
        guard let codableType = type as? any (Codable & Sendable).Type else {
            throw ActorEdgeError.serializationFailed(
                "Type \(type) does not conform to Codable & Sendable"
            )
        }
        
        return try deserializeErased(codableType, from: buffer, userInfo: userInfo)
    }
    
    /// Type-erased deserialization helper
    private func deserializeErased(
        _ type: any (Codable & Sendable).Type,
        from buffer: SerializationBuffer,
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> Any {
        // Set up decoder with user info
        var combinedUserInfo = userInfo
        if combinedUserInfo[.actorSystemKey] == nil {
            combinedUserInfo[.actorSystemKey] = system
        }
        decoder.userInfo = combinedUserInfo
        
        let data = buffer.readData()
        return try decoder.decode(type, from: data)
    }
}

// MARK: - CodingUserInfoKey Extensions
extension CodingUserInfoKey {
    /// Key for storing the actor system in decoder's userInfo
    public static let actorSystemKey = CodingUserInfoKey(rawValue: "distributed_actor_system")!
}