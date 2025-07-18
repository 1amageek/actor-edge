import Distributed
import Foundation

/// Encoder for distributed actor method invocations
/// Based on swift-distributed-actors ClusterInvocationEncoder patterns
public struct ActorEdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State (following swift-distributed-actors pattern)
    
    /// Serialized arguments as Data array
    private(set) var arguments: [Data] = []
    
    /// Generic type substitutions as mangled type names
    private(set) var genericSubstitutions: [String] = []
    
    /// Return type information (optional)
    private var returnTypeInfo: String?
    
    /// Error type information (optional) 
    private var errorTypeInfo: String?
    
    /// Indicates if the method throws
    private(set) var throwing: Bool = false
    
    /// Current encoding state
    internal private(set) var state: InvocationEncoderState = .recording
    
    /// Reference to the actor system for serialization
    private let system: ActorEdgeSystem
    
    /// Serialization system for encoding arguments
    private var serialization: ActorEdgeSerialization {
        system.serialization
    }
    
    // MARK: - Initialization
    
    public init(system: ActorEdgeSystem) {
        self.system = system
    }
    
    // MARK: - DistributedTargetInvocationEncoder Implementation
    // Following Apple's documented method call order
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record after doneRecording()")
        }
        
        // Use String(reflecting:) to get type name, similar to swift-distributed-actors
        let typeName = String(reflecting: type)
        genericSubstitutions.append(typeName)
    }
    
    public mutating func recordArgument<Argument>(
        _ argument: RemoteCallArgument<Argument>
    ) throws where Argument: SerializationRequirement {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record after doneRecording()")
        }
        
        // Serialize argument value using ActorEdgeSerialization
        let buffer = try serialization.serialize(argument.value)
        arguments.append(buffer.readData())
    }
    
    public mutating func recordReturnType<R>(
        _ returnType: R.Type
    ) throws where R: SerializationRequirement {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record after doneRecording()")
        }
        
        // Record return type info (not used in swift-distributed-actors, but kept for completeness)
        returnTypeInfo = String(reflecting: returnType)
    }
    
    public mutating func recordErrorType<E: Error>(_ errorType: E.Type) throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Cannot record after doneRecording()")
        }
        
        // Set throwing flag (following ClusterInvocationEncoder pattern)
        throwing = true
        errorTypeInfo = String(reflecting: errorType)
    }
    
    public mutating func doneRecording() throws {
        guard state == .recording else {
            throw ActorEdgeError.invocationError("Already completed recording")
        }
        
        state = .completed
    }
    
    // MARK: - Internal Access Methods
    
    /// Create an InvocationMessage from the recorded data
    /// Used by ActorEdgeSystem for remote calls
    public func createInvocationMessage(
        callID: String = CallIDGenerator.generate(),
        targetIdentifier: String
    ) throws -> InvocationMessage {
        guard state == .completed else {
            throw ActorEdgeError.invocationError("Must call doneRecording() first")
        }
        
        return InvocationMessage(
            callID: callID,
            targetIdentifier: targetIdentifier,
            genericSubstitutions: genericSubstitutions,
            arguments: arguments
        )
    }
    
}