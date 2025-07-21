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

/// Encoder for distributed actor method invocations.
///
/// This encoder implements Swift Distributed's `DistributedTargetInvocationEncoder`
/// protocol to capture method invocation details for transport across the network.
/// It follows the exact API contract required by the Swift runtime.
public struct ActorEdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State
    
    /// Serialized arguments with their manifests
    private var arguments: [SerializedArgument] = []
    
    /// Generic type substitutions as mangled type names
    private var genericSubstitutions: [String] = []
    
    /// Whether the method returns Void
    private var isVoid: Bool = false
    
    /// Whether the method can throw
    private var canThrow: Bool = false
    
    /// Return type information (mangled type name)
    private var returnType: String?
    
    /// Error type information (mangled type name)
    private var errorType: String?
    
    /// Current encoding state
    internal private(set) var state: EncodingState = .recording
    
    /// Reference to the actor system
    private let system: ActorEdgeSystem
    
    // MARK: - Initialization
    
    public init(system: ActorEdgeSystem) {
        self.system = system
    }
    
    // MARK: - DistributedTargetInvocationEncoder Implementation
    // Following Apple's documented method call order
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record generic substitution after doneRecording()")
        }
        
        // swift-distributed-actors準拠の実装
        let mangledName = _mangledTypeName(type) ?? _typeName(type)
        genericSubstitutions.append(mangledName)
    }
    
    public mutating func recordArgument<Argument>(
        _ argument: RemoteCallArgument<Argument>
    ) throws where Argument: SerializationRequirement {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record argument after doneRecording()")
        }
        
        // Serialize using the new SerializationSystem
        let serialized = try system.serialization.serialize(argument.value)
        
        arguments.append(SerializedArgument(
            data: serialized.data,
            manifest: serialized.manifest,
            label: argument.label
        ))
    }
    
    public mutating func recordReturnType<R>(
        _ returnType: R.Type
    ) throws where R: SerializationRequirement {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record return type after doneRecording()")
        }
        
        // Check if void return
        isVoid = returnType == Void.self
        self.returnType = String(reflecting: returnType)
    }
    
    public mutating func recordErrorType<E: Error>(_ errorType: E.Type) throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record error type after doneRecording()")
        }
        
        // Mark as throwing method
        canThrow = true
        self.errorType = String(reflecting: errorType)
    }
    
    public mutating func doneRecording() throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Already completed recording")
        }
        
        state = .completed
    }
    
    // MARK: - Internal Access Methods
    
    /// Finalizes the invocation data for envelope creation.
    /// This method is called by DistributedInvocationProcessor.
    internal func finalizeInvocation() throws -> InvocationData {
        guard state == .completed else {
            throw ActorEdgeError.invocationError("Must call doneRecording() before finalizing")
        }
        
        // Extract data and manifests from SerializedArgument array
        let argumentData = arguments.map { $0.data }
        let argumentManifests = arguments.map { $0.manifest }
        
        return InvocationData(
            arguments: argumentData,
            argumentManifests: argumentManifests,
            genericSubstitutions: genericSubstitutions,
            isVoid: isVoid
        )
    }
}

// MARK: - Supporting Types

/// Encoding state tracking
internal enum EncodingState {
    case recording
    case completed
}

// Errors moved to ActorEdgeError