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

import Distributed
import Foundation

/// Decoder for distributed actor method invocations.
///
/// This decoder implements Swift Distributed's `DistributedTargetInvocationDecoder`
/// protocol to reconstruct method invocations from serialized data received
/// over the network.
public struct ActorEdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State
    
    /// Current decoding state
    private let state: DecodingState
    
    /// Reference to the actor system
    private let system: ActorEdgeSystem
    
    /// Current argument index for sequential decoding
    private var argumentIndex: Int = 0
    
    /// The original envelope (for context)
    private let envelope: Envelope?
    
    // MARK: - Initialization
    
    /// Initialize from invocation data and envelope.
    /// Used by DistributedInvocationProcessor.
    internal init(
        system: ActorEdgeSystem,
        invocationData: InvocationData,
        envelope: Envelope? = nil
    ) {
        self.system = system
        self.state = .remoteCall(invocationData)
        self.envelope = envelope
    }
    
    /// Initialize from a local encoder (for optimization).
    internal init(
        system: ActorEdgeSystem,
        encoder: ActorEdgeInvocationEncoder
    ) {
        self.system = system
        self.state = .localCall(encoder)
        self.envelope = nil
    }
    
    // MARK: - DistributedTargetInvocationDecoder Implementation
    // Following Apple's specification for proper order and behavior
    
    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        let substitutions: [String]
        
        switch state {
        case .remoteCall(let data):
            substitutions = data.genericSubstitutions
        case .localCall(let encoder):
            // Get from finalized invocation data
            let invocationData = try encoder.finalizeInvocation()
            substitutions = invocationData.genericSubstitutions
        }
        
        // Optimized for concrete types (most common case)
        if substitutions.isEmpty {
            return []
        }
        
        // Handle generic type resolution
        var types: [Any.Type] = []
        for mangledName in substitutions {
            if let type = _typeByName(mangledName) {
                types.append(type)
            } else {
                // Log warning and use Any.self as fallback
                system.log("Cannot resolve generic type '\(mangledName)', using Any.self")
                types.append(Any.self)
            }
        }
        
        return types
    }
    
    public mutating func decodeNextArgument<Argument>() throws -> Argument 
    where Argument: SerializationRequirement {
        let argumentData: Data
        let manifest: SerializationManifest
        
        switch state {
        case .remoteCall(let data):
            guard argumentIndex < data.arguments.count else {
                throw DecodingError.notEnoughArguments(
                    expected: argumentIndex + 1,
                    actual: data.arguments.count
                )
            }
            argumentData = data.arguments[argumentIndex]
            if argumentIndex < data.argumentManifests.count {
                manifest = data.argumentManifests[argumentIndex]
            } else {
                manifest = SerializationManifest.json()
            }
            
        case .localCall(let encoder):
            let invocationData = try encoder.finalizeInvocation()
            guard argumentIndex < invocationData.arguments.count else {
                throw DecodingError.notEnoughArguments(
                    expected: argumentIndex + 1,
                    actual: invocationData.arguments.count
                )
            }
            argumentData = invocationData.arguments[argumentIndex]
            if argumentIndex < invocationData.argumentManifests.count {
                manifest = invocationData.argumentManifests[argumentIndex]
            } else {
                manifest = SerializationManifest.json()
            }
        }
        
        argumentIndex += 1
        
        // Deserialize using the new SerializationSystem
        let decoder = JSONDecoder()
        decoder.userInfo[.actorSystemKey] = system
        
        // Special handling for distributed actors
        if Argument.self is any DistributedActor.Type {
            // For now, we'll deserialize the actor ID and resolve it
            // This is a simplified implementation
            if let actorIDString = String(data: argumentData, encoding: .utf8) {
                let _ = ActorEdgeID(actorIDString)
                // Try to resolve the actor locally
                // Note: This is a simplified version - the actual implementation
                // would need proper type checking and casting
                throw DecodingError.typeMismatch(
                    expected: String(describing: Argument.self),
                    actual: "Distributed actor deserialization not fully implemented"
                )
            }
            throw DecodingError.typeMismatch(
                expected: String(describing: Argument.self),
                actual: "Could not decode distributed actor reference"
            )
        }
        
        // Regular deserialization
        return try system.serialization.deserialize(
            argumentData,
            as: Argument.self,
            using: manifest
        )
    }
    
    public mutating func decodeReturnType() throws -> Any.Type? {
        // Return type information is not stored in the simplified design
        // The runtime already knows the return type from the method signature
        return nil
    }
    
    public mutating func decodeErrorType() throws -> Any.Type? {
        // Error type information is not stored in the simplified design
        // The runtime already knows the error type from the method signature
        return nil
    }
    
}

// MARK: - Supporting Types

/// Decoding state
private enum DecodingState {
    case remoteCall(InvocationData)
    case localCall(ActorEdgeInvocationEncoder)
}

/// Decoding-specific errors
private enum DecodingError: Error {
    case notEnoughArguments(expected: Int, actual: Int)
    case typeMismatch(expected: String, actual: String)
}

// MARK: - Type Resolution

/// Attempts to resolve a type from its mangled name.
/// This is a simplified version - production would use swift-demangle.
private func _typeByName(_ mangledName: String) -> Any.Type? {
    // Try common built-in types first
    switch mangledName {
    case "Swift.String", "String":
        return String.self
    case "Swift.Int", "Int":
        return Int.self
    case "Swift.Double", "Double":
        return Double.self
    case "Swift.Bool", "Bool":
        return Bool.self
    case "Swift.Array<Swift.String>":
        return [String].self
    case "Swift.Dictionary<Swift.String, Swift.String>":
        return [String: String].self
    default:
        // For now, return nil for unknown types
        // In production, this would use swift-demangle or a type registry
        return nil
    }
}

// MARK: - CodingUserInfoKey Extension

extension CodingUserInfoKey {
    /// Key for storing the actor system in decoder's userInfo
    static let actorSystemKey = CodingUserInfoKey(rawValue: "org.swift.actoredge.system")!
}