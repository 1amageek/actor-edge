//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Distributed

/// A unified serialization system for distributed actor messages.
///
/// This system manages multiple serializers and provides a consistent interface
/// for serializing and deserializing actor messages with proper type safety
/// and manifest generation.
public final class SerializationSystem: Sendable {
    private let registry: SerializerRegistry
    private let defaultSerializerID: String
    
    /// Creates a new serialization system with default JSON serializer.
    public init(defaultSerializerID: String = SerializationManifest.jsonSerializerID) {
        self.registry = SerializerRegistry()
        self.defaultSerializerID = defaultSerializerID
        registerDefaultSerializers()
    }
    
    /// Serializes a value using the appropriate serializer.
    public func serialize<T: Codable>(_ value: T, using serializerID: String? = nil) throws -> SerializedMessage {
        let id = serializerID ?? defaultSerializerID
        let serializer = try registry.getSerializer(id: id)
        let data = try serializer.serialize(value)
        
        let manifest = SerializationManifest(
            serializerID: id,
            hint: mangledTypeName(T.self)
        )
        
        return SerializedMessage(data: data, manifest: manifest)
    }
    
    /// Deserializes data using the manifest information.
    public func deserialize<T: Codable>(
        _ data: Data,
        as type: T.Type,
        using manifest: SerializationManifest
    ) throws -> T {
        let serializer = try registry.getSerializer(id: manifest.serializerID)
        return try serializer.deserialize(data, as: type)
    }
    
    /// Deserializes a SerializedMessage.
    public func deserialize<T: Codable>(
        _ message: SerializedMessage,
        as type: T.Type
    ) throws -> T {
        return try deserialize(message.data, as: type, using: message.manifest)
    }
    
    /// Registers a custom serializer.
    public func register(serializer: any MessageSerializer, for id: String) {
        registry.register(serializer: serializer, for: id)
    }
    
    private func registerDefaultSerializers() {
        // Register JSON serializer
        registry.register(
            serializer: JSONMessageSerializer(),
            for: SerializationManifest.jsonSerializerID
        )
        
        // TODO: Register other serializers (protobuf, msgpack, etc.)
    }
    
    private func mangledTypeName<T>(_ type: T.Type) -> String {
        return String(reflecting: type)
    }
}

/// Protocol for message serializers.
public protocol MessageSerializer: Sendable {
    /// The version of this serializer.
    var version: String { get }
    
    /// Additional attributes for this serializer.
    var attributes: [String: String] { get }
    
    /// Serializes a value to data.
    func serialize<T: Codable>(_ value: T) throws -> Data
    
    /// Deserializes data to a value.
    func deserialize<T: Codable>(_ data: Data, as type: T.Type) throws -> T
}

/// Thread-safe registry for message serializers.
final class SerializerRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var serializers: [String: any MessageSerializer] = [:]
    
    func register(serializer: any MessageSerializer, for id: String) {
        lock.withLock {
            serializers[id] = serializer
        }
    }
    
    func getSerializer(id: String) throws -> any MessageSerializer {
        try lock.withLock {
            guard let serializer = serializers[id] else {
                throw SerializationError.serializerNotFound(id: id)
            }
            return serializer
        }
    }
}

/// JSON-based message serializer.
struct JSONMessageSerializer: MessageSerializer {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    var version: String { "1.0" }
    var attributes: [String: String] { [:] }
    
    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    func serialize<T: Codable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw SerializationError.encodingFailed(error: error)
        }
    }
    
    func deserialize<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SerializationError.decodingFailed(error: error)
        }
    }
}

/// Errors that can occur during serialization.
public enum SerializationError: Error, Sendable {
    case serializerNotFound(id: String)
    case encodingFailed(error: Error)
    case decodingFailed(error: Error)
    case typeMismatch(expected: String, actual: String)
    case unsupportedType(String)
}

// MARK: - Extensions for ActorSystem Integration

extension SerializationSystem {
    /// Special handling for distributed actor references.
    public func serializeActorReference<Act: DistributedActor>(
        _ actor: Act
    ) throws -> SerializedMessage where Act.ActorSystem == ActorEdgeSystem {
        let reference = ActorReference(id: actor.id, type: String(reflecting: Act.self))
        return try serialize(reference)
    }
    
    /// Deserializes an actor reference.
    public func deserializeActorReference<Act: DistributedActor>(
        _ message: SerializedMessage,
        as actorType: Act.Type,
        using system: ActorEdgeSystem
    ) async throws -> Act where Act.ActorSystem == ActorEdgeSystem {
        let reference = try deserialize(message, as: ActorReference.self)
        
        // Resolve the actor using the system
        guard let actor = try system.resolve(id: reference.id, as: actorType) else {
            throw SerializationError.typeMismatch(
                expected: String(reflecting: actorType),
                actual: reference.type
            )
        }
        
        return actor
    }
}

/// Internal representation of an actor reference for serialization.
private struct ActorReference: Codable {
    let id: ActorEdgeID
    let type: String
}