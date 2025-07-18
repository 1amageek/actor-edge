import Distributed
import Foundation

/// Decoder for distributed actor method invocations
/// Based on swift-distributed-actors ClusterInvocationDecoder patterns
public struct ActorEdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State (following swift-distributed-actors pattern)
    
    /// Current decoding state
    private let state: InvocationDecoderState
    
    /// Reference to the actor system for actor resolution
    private let system: ActorEdgeSystem
    
    /// Current argument index for sequential decoding
    private var argumentIndex: Int = 0
    
    /// Serialization system for decoding arguments
    private var serialization: ActorEdgeSerialization {
        system.serialization
    }
    
    // MARK: - Initialization
    
    /// Initialize from a remote call message
    public init(system: ActorEdgeSystem, message: InvocationMessage) {
        self.system = system
        self.state = .remoteCall(message)
    }
    
    /// Initialize from a local call encoder (for proxy optimization)
    public init(system: ActorEdgeSystem, encoder: ActorEdgeInvocationEncoder) {
        self.system = system
        self.state = .localCall(encoder)
    }
    
    /// Initialize from serialized payload
    public init(system: ActorEdgeSystem, payload: Data) throws {
        self.system = system
        
        // Decode as InvocationMessage
        let buffer = SerializationBuffer.data(payload)
        let message = try system.serialization.deserialize(InvocationMessage.self, from: buffer)
        self.state = .remoteCall(message)
    }
    
    // MARK: - DistributedTargetInvocationDecoder Implementation
    // Following Apple's specification for proper order and behavior
    
    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        let substitutions: [String]
        
        switch state {
        case .remoteCall(let message):
            substitutions = message.genericSubstitutions
        case .localCall(let encoder):
            substitutions = encoder.genericSubstitutions
        }
        
        // Optimized for concrete types (most common case)
        if substitutions.isEmpty {
            return [] // Most distributed actor calls use concrete types
        }
        
        // Handle generic type resolution with graceful fallback
        var types: [Any.Type] = []
        for typeName in substitutions {
            if let type = TypeResolver.resolveType(from: typeName) {
                types.append(type)
            } else {
                // Log warning and use Any.self as fallback instead of throwing
                print("Warning: Cannot resolve generic type '\(typeName)', using Any.self")
                types.append(Any.self)
            }
        }
        
        return types
    }
    
    public mutating func decodeNextArgument<Argument>() throws -> Argument 
    where Argument: SerializationRequirement {
        let argumentData: Data
        
        switch state {
        case .remoteCall(let message):
            guard argumentIndex < message.arguments.count else {
                throw ActorEdgeError.deserializationFailed(
                    "Not enough arguments: expected \(argumentIndex + 1), have \(message.arguments.count)"
                )
            }
            argumentData = message.arguments[argumentIndex]
            
        case .localCall(let encoder):
            guard argumentIndex < encoder.arguments.count else {
                throw ActorEdgeError.deserializationFailed(
                    "Not enough arguments: expected \(argumentIndex + 1), have \(encoder.arguments.count)"
                )
            }
            argumentData = encoder.arguments[argumentIndex]
        }
        
        argumentIndex += 1
        
        // Decode the argument using ActorEdgeSerialization
        // This automatically sets userInfo[.actorSystemKey] for distributed actor arguments
        let buffer = SerializationBuffer.data(argumentData)
        return try serialization.deserialize(Argument.self, from: buffer)
    }
    
    public mutating func decodeReturnType() throws -> Any.Type? {
        // Return type decoding is not implemented in swift-distributed-actors either
        // This method exists for protocol conformance but returns nil
        return nil
    }
    
    public mutating func decodeErrorType() throws -> Any.Type? {
        // Error type decoding is not implemented in swift-distributed-actors either  
        // This method exists for protocol conformance but returns nil
        return nil
    }
    
    // MARK: - Internal Access Methods
    
    /// Get the target identifier from the invocation
    internal var targetIdentifier: String {
        switch state {
        case .remoteCall(let message):
            return message.targetIdentifier
        case .localCall(_):
            return "local-call"
        }
    }
    
    /// Get the call ID from the invocation (if available)
    internal var callID: String? {
        switch state {
        case .remoteCall(let message):
            return message.callID
        case .localCall(_):
            return nil
        }
    }
}