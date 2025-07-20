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

/// Represents the serialized data for a distributed method invocation.
public struct InvocationData: Codable, Sendable {
    /// Serialized arguments for the method call
    public let arguments: [Data]
    
    /// Serialization manifests for each argument
    public let argumentManifests: [SerializationManifest]
    
    /// Generic type substitutions (mangled type names)
    public let genericSubstitutions: [String]
    
    /// Whether the method returns Void
    public let isVoid: Bool
    
    public init(
        arguments: [Data] = [],
        argumentManifests: [SerializationManifest] = [],
        genericSubstitutions: [String] = [],
        isVoid: Bool = false
    ) {
        self.arguments = arguments
        self.argumentManifests = argumentManifests
        self.genericSubstitutions = genericSubstitutions
        self.isVoid = isVoid
    }
}

/// Represents a single serialized argument.
public struct SerializedArgument: Codable, Sendable {
    /// The serialized argument data
    public let data: Data
    
    /// Serialization manifest for this argument
    public let manifest: SerializationManifest
    
    /// Parameter label (if any)
    public let label: String?
    
    public init(
        data: Data,
        manifest: SerializationManifest,
        label: String? = nil
    ) {
        self.data = data
        self.manifest = manifest
        self.label = label
    }
}

/// Result of a distributed method invocation.
public enum InvocationResult: Codable, Sendable {
    /// Successful return with serialized value
    case success(SerializedMessage)
    
    /// Successful void return
    case void
    
    /// Error thrown during invocation
    case error(SerializedError)
    
    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "success":
            let message = try container.decode(SerializedMessage.self, forKey: .value)
            self = .success(message)
        case "void":
            self = .void
        case "error":
            let error = try container.decode(SerializedError.self, forKey: .value)
            self = .error(error)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown result type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .success(let message):
            try container.encode("success", forKey: .type)
            try container.encode(message, forKey: .value)
        case .void:
            try container.encode("void", forKey: .type)
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .value)
        }
    }
}

/// Represents a serialized error.
public struct SerializedError: Codable, Sendable {
    /// The error type (mangled type name)
    public let type: String
    
    /// Human-readable error message (fallback)
    public let message: String
    
    /// Serialized error data (optional if error is not Codable)
    public let serializedError: Data?
    
    public init(
        type: String,
        message: String,
        serializedError: Data? = nil
    ) {
        self.type = type
        self.message = message
        self.serializedError = serializedError
    }
}