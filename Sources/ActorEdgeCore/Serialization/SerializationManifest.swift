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

/// Describes how a serialized payload should be deserialized.
///
/// Based on swift-distributed-actors' Manifest design, this provides
/// minimal metadata for serialization: serializerID and hint.
public struct SerializationManifest: Sendable, Codable, Equatable {
    /// The identifier of the serializer used (e.g., "1" for JSON, "2" for protobuf)
    public let serializerID: String
    
    /// Type hint for deserialization
    public let hint: String
    
    public init(serializerID: String, hint: String = "") {
        self.serializerID = serializerID
        self.hint = hint
    }
}

// MARK: - Common Manifests

extension SerializationManifest {
    /// JSON serializer ID 
    public static let jsonSerializerID = "json"
    
    /// Protobuf serializer ID
    public static let protobufSerializerID = "protobuf"
    
    /// Creates a manifest for JSON serialization.
    public static func json(hint: String = "") -> SerializationManifest {
        return SerializationManifest(serializerID: jsonSerializerID, hint: hint)
    }
    
    /// Creates a manifest for Protocol Buffers serialization.
    public static func protobuf(hint: String = "") -> SerializationManifest {
        return SerializationManifest(serializerID: protobufSerializerID, hint: hint)
    }
}


/// Result of a serialization operation.
public struct SerializedMessage: Sendable, Codable {
    /// The serialized data
    public let data: Data
    
    /// The manifest describing the serialization
    public let manifest: SerializationManifest
    
    public init(data: Data, manifest: SerializationManifest) {
        self.data = data
        self.manifest = manifest
    }
}