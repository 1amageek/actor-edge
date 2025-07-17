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
    
    /// JSON decoder with proper configuration
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    /// Initialize from a remote call message
    public init(system: ActorEdgeSystem, message: InvocationMessage) {
        self.system = system
        self.state = .remoteCall(message)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        // CRITICAL: Set actor system in userInfo for distributed actor deserialization
        // This is required by Apple's specification for distributed actor arguments
        self.decoder.userInfo[.actorSystemKey] = system
    }
    
    /// Initialize from a local call encoder (for proxy optimization)
    public init(system: ActorEdgeSystem, encoder: ActorEdgeInvocationEncoder) {
        self.system = system
        self.state = .localCall(encoder)
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        // CRITICAL: Set actor system in userInfo for distributed actor deserialization
        self.decoder.userInfo[.actorSystemKey] = system
    }
    
    /// Legacy initialization for backward compatibility
    public init(system: ActorEdgeSystem, payload: Data) throws {
        self.system = system
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.userInfo[.actorSystemKey] = system
        
        // Try to decode as InvocationMessage first
        if let message = try? decoder.decode(InvocationMessage.self, from: payload) {
            self.state = .remoteCall(message)
        } else {
            // Fallback to legacy envelope format
            let envelope = try decoder.decode(InvocationEnvelope.self, from: payload)
            let message = InvocationMessage(
                targetIdentifier: "unknown",
                genericSubstitutions: envelope.genericSubstitutions,
                arguments: envelope.arguments
            )
            self.state = .remoteCall(message)
        }
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
        
        // Decode the argument with proper actor system context
        // The decoder.userInfo[.actorSystemKey] is crucial for distributed actor arguments
        return try decoder.decode(Argument.self, from: argumentData)
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

/// Legacy container for backward compatibility
/// Will be removed once all systems use InvocationMessage
private struct InvocationEnvelope: Codable {
    let arguments: [Data]
    let genericSubstitutions: [String]
    let returnType: String?
    let errorType: String?
}