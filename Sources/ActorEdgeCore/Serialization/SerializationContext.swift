//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import Foundation
import Distributed

/// A simplified serialization context that provides necessary information
/// for serializing and deserializing values in a distributed actor system.
public final class SerializationContext: Sendable {
    /// The actor system associated with this context.
    public let actorSystem: ActorEdgeSystem
    
    /// The distributed actor resolver for actor references.
    public let distributedActorResolver: DistributedActorResolver
    
    /// Context-specific metadata.
    private let metadata: [String: String]
    
    /// Thread-safe storage for context values.
    private let contextStorage = ContextStorage()
    
    /// Creates a new serialization context.
    public init(
        actorSystem: ActorEdgeSystem,
        metadata: [String: String] = [:]
    ) {
        self.actorSystem = actorSystem
        self.distributedActorResolver = DistributedActorResolver(actorSystem: actorSystem)
        self.metadata = metadata
    }
    
    // MARK: - Actor Serialization
    
    /// Serializes a distributed actor reference.
    public func serializeActor<Act: DistributedActor>(_ actor: Act) throws -> ActorReference 
    where Act.ActorSystem == ActorEdgeSystem {
        return ActorReference(
            id: actor.id,
            typeName: String(reflecting: Act.self),
            systemType: String(reflecting: Act.ActorSystem.self),
            metadata: extractActorMetadata(from: actor)
        )
    }
    
    /// Deserializes a distributed actor reference.
    public func deserializeActor<Act: DistributedActor>(
        _ reference: ActorReference,
        as actorType: Act.Type
    ) throws -> Act where Act.ActorSystem == ActorEdgeSystem {
        // Validate type compatibility
        let expectedType = String(reflecting: actorType)
        let actualType = reference.typeName
        
        guard actualType == expectedType else {
            throw ActorEdgeError.typeMismatch(expected: expectedType, actual: actualType)
        }
        
        // Resolve the actor through the system
        return try distributedActorResolver.resolve(id: reference.id, as: actorType)
    }
    
    // MARK: - Type Registration
    
    /// No longer needed - types are handled by Swift's type system
    @available(*, deprecated, message: "Type registration is no longer needed")
    public func registerType<T: Codable & Sendable>(_ type: T.Type) {
        // No-op for backward compatibility
    }
    
    /// No longer needed - distributed actors are handled by Swift's type system
    @available(*, deprecated, message: "Distributed actor registration is no longer needed")
    public func registerDistributedActor<Act: DistributedActor>(_ actorType: Act.Type) 
    where Act.ActorSystem == ActorEdgeSystem {
        // No-op for backward compatibility
    }
    
    // MARK: - Context Storage
    
    /// Sets a value in the context storage.
    public func setValue<T: Sendable>(_ value: T, forKey key: String) {
        contextStorage.setValue(value, forKey: key)
    }
    
    /// Gets a value from the context storage.
    public func getValue<T: Sendable>(_ type: T.Type, forKey key: String) -> T? {
        return contextStorage.getValue(type, forKey: key)
    }
    
    /// Removes a value from the context storage.
    public func removeValue(forKey key: String) {
        contextStorage.removeValue(forKey: key)
    }
    
    // MARK: - Metadata
    
    /// Gets metadata value for a key.
    public func metadata(forKey key: String) -> String? {
        return metadata[key]
    }
    
    /// Creates a child context with additional metadata.
    public func withMetadata(_ additionalMetadata: [String: String]) -> SerializationContext {
        var newMetadata = metadata
        newMetadata.merge(additionalMetadata) { _, new in new }
        
        return SerializationContext(
            actorSystem: actorSystem,
            metadata: newMetadata
        )
    }
    
    // MARK: - Private Helpers
    
    private func extractActorMetadata<Act: DistributedActor>(from actor: Act) -> [String: String] {
        var metadata: [String: String] = [:]
        
        // Add actor-specific metadata
        metadata["actorType"] = String(describing: type(of: actor))
        metadata["systemType"] = String(describing: type(of: actor.actorSystem))
        
        // Custom metadata support removed for simplification
        
        return metadata
    }
}

// MARK: - Distributed Actor Resolver

/// Resolves distributed actor references within an actor system.
public final class DistributedActorResolver: Sendable {
    private let actorSystem: ActorEdgeSystem
    
    init(actorSystem: ActorEdgeSystem) {
        self.actorSystem = actorSystem
    }
    
    /// Resolves a distributed actor by ID.
    public func resolve<Act: DistributedActor>(
        id: ActorEdgeID,
        as actorType: Act.Type
    ) throws -> Act where Act.ActorSystem == ActorEdgeSystem {
        // First try to resolve locally
        if let localActor = try actorSystem.resolve(id: id, as: actorType) {
            return localActor
        }
        
        // For remote actors, the system returns nil and Swift runtime creates a proxy
        // The proxy is created by the @Resolvable macro
        throw ActorEdgeError.actorNotFound(id)
    }
    
    /// Checks if an actor ID represents a local actor.
    public func isLocal(id: ActorEdgeID) -> Bool {
        // Check if the actor exists in the registry
        return actorSystem.registry?.find(id: id) != nil
    }
}

// MARK: - Actor Reference

/// A serializable reference to a distributed actor.
public struct ActorReference: Sendable, Codable {
    /// The actor's unique identifier.
    public let id: ActorEdgeID
    
    /// The type name of the actor.
    public let typeName: String
    
    /// The actor system type.
    public let systemType: String
    
    /// Additional metadata about the actor.
    public let metadata: [String: String]
    
    public init(
        id: ActorEdgeID,
        typeName: String,
        systemType: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.typeName = typeName
        self.systemType = systemType
        self.metadata = metadata
    }
}

// MARK: - Context Storage

/// Thread-safe storage for context values.
private final class ContextStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    
    func setValue<T: Sendable>(_ value: T, forKey key: String) {
        lock.withLock {
            storage[key] = value
        }
    }
    
    func getValue<T: Sendable>(_ type: T.Type, forKey key: String) -> T? {
        lock.withLock {
            return storage[key] as? T
        }
    }
    
    func removeValue(forKey key: String) {
        _ = lock.withLock {
            storage.removeValue(forKey: key)
        }
    }
}

// MARK: - Protocols removed for simplification

// MARK: - Errors moved to unified ActorEdgeError

// MARK: - Decoder Integration

extension CodingUserInfoKey {
    /// The key for storing the serialization context in a decoder's userInfo.
    public static let serializationContext = CodingUserInfoKey(rawValue: "ActorEdge.SerializationContext")!
    
    /// The key for storing the actor system in a decoder's userInfo.
    public static let actorSystem = CodingUserInfoKey(rawValue: "ActorEdge.ActorSystem")!
}

// MARK: - JSON Integration

extension SerializationContext {
    /// Creates a properly configured JSONEncoder for this context.
    public func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.userInfo[.serializationContext] = self
        encoder.userInfo[.actorSystem] = actorSystem
        return encoder
    }
    
    /// Creates a properly configured JSONDecoder for this context.
    public func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[.serializationContext] = self
        decoder.userInfo[.actorSystem] = actorSystem
        return decoder
    }
}