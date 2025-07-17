import Foundation
import Distributed

/// Message structure for remote actor invocations
/// Based on swift-distributed-actors InvocationMessage
public struct InvocationMessage: Codable, Sendable {
    /// Unique identifier for this call
    public let callID: String
    
    /// Target method identifier (mangled name)
    public let targetIdentifier: String
    
    /// Generic type substitutions for the method
    public let genericSubstitutions: [String]
    
    /// Serialized arguments
    public let arguments: [Data]
    
    public init(
        callID: String,
        targetIdentifier: String,
        genericSubstitutions: [String],
        arguments: [Data]
    ) {
        self.callID = callID
        self.targetIdentifier = targetIdentifier
        self.genericSubstitutions = genericSubstitutions
        self.arguments = arguments
    }
    
    /// Convert to RemoteCallTarget
    public var target: Distributed.RemoteCallTarget {
        Distributed.RemoteCallTarget(targetIdentifier)
    }
}

// MARK: - CustomStringConvertible
extension InvocationMessage: CustomStringConvertible {
    public var description: String {
        "InvocationMessage(callID: \(callID), target: \(targetIdentifier), args: \(arguments.count))"
    }
}