import Foundation

/// Message structure for distributed actor method invocations
/// Based on swift-distributed-actors InvocationMessage pattern
public struct InvocationMessage: Codable, Sendable {
    /// Unique identifier for this remote call
    public let callID: String
    
    /// String identifier of the target method (from RemoteCallTarget)
    public let targetIdentifier: String
    
    /// Array of mangled type names for generic substitutions
    public let genericSubstitutions: [String]
    
    /// Serialized arguments as Data array
    public let arguments: [Data]
    
    /// Optional metadata for tracing and debugging
    public let metadata: [String: String]
    
    public init(
        callID: String = UUID().uuidString,
        targetIdentifier: String,
        genericSubstitutions: [String] = [],
        arguments: [Data] = [],
        metadata: [String: String] = [:]
    ) {
        self.callID = callID
        self.targetIdentifier = targetIdentifier
        self.genericSubstitutions = genericSubstitutions
        self.arguments = arguments
        self.metadata = metadata
    }
}

/// Reply message for remote call results
/// Based on swift-distributed-actors RemoteCallReply pattern
public struct RemoteCallReply: Codable, Sendable {
    /// Call ID this reply corresponds to
    public let callID: String
    
    /// Success value data (nil if error)
    public let value: Data?
    
    /// Error information (nil if success)
    public let error: RemoteCallError?
    
    /// Optional metadata
    public let metadata: [String: String]
    
    public init(
        callID: String,
        value: Data? = nil,
        error: RemoteCallError? = nil,
        metadata: [String: String] = [:]
    ) {
        self.callID = callID
        self.value = value
        self.error = error
        self.metadata = metadata
    }
    
    /// Create a successful reply
    public static func success(
        callID: String,
        value: Data,
        metadata: [String: String] = [:]
    ) -> RemoteCallReply {
        RemoteCallReply(
            callID: callID,
            value: value,
            metadata: metadata
        )
    }
    
    /// Create an error reply
    public static func failure(
        callID: String,
        error: RemoteCallError,
        metadata: [String: String] = [:]
    ) -> RemoteCallReply {
        RemoteCallReply(
            callID: callID,
            error: error,
            metadata: metadata
        )
    }
    
    /// Get the result as a Swift Result type
    public var result: Result<Data, RemoteCallError> {
        if let value = value {
            return .success(value)
        } else if let error = error {
            return .failure(error)
        } else {
            return .failure(.generic("Invalid reply: no value or error"))
        }
    }
}

/// Error types for remote calls
public enum RemoteCallError: Error, Codable, Sendable {
    /// Generic error with description
    case generic(String)
    
    /// Codable error that was serialized from the remote side
    case codableError(Data, typeName: String)
    
    /// Method not found error
    case methodNotFound(String)
    
    /// Argument decoding error
    case argumentDecodingError(String)
    
    /// Actor not found error
    case actorNotFound(String)
    
    /// Timeout error
    case timeout
    
    /// Network/transport error
    case transportError(String)
}

/// Special marker type for void returns (similar to swift-distributed-actors _Done)
public struct VoidReturn: Codable, Sendable {
    public init() {}
}