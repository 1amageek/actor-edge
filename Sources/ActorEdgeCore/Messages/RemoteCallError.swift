import Foundation

/// Error information for remote calls
/// Based on swift-distributed-actors RemoteCallError and GenericRemoteCallError patterns
public enum RemoteCallError: Codable, Sendable, Error {
    /// A generic error with just a message (like GenericRemoteCallError)
    case generic(String)
    
    /// A codable error that was serialized
    case codableError(Data, typeName: String)
    
    /// System already shut down
    case systemShutDown
    
    /// Call timed out
    case timedOut(callID: String)
    
    /// Invalid reply received
    case invalidReply(callID: String)
    
    /// Illegal reply type
    case illegalReplyType(callID: String, expected: String, got: String)
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case data
        case typeName
        case callID
        case expected
        case got
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "generic":
            let message = try container.decode(String.self, forKey: .message)
            self = .generic(message)
        case "codableError":
            let data = try container.decode(Data.self, forKey: .data)
            let typeName = try container.decode(String.self, forKey: .typeName)
            self = .codableError(data, typeName: typeName)
        case "systemShutDown":
            self = .systemShutDown
        case "timedOut":
            let callID = try container.decode(String.self, forKey: .callID)
            self = .timedOut(callID: callID)
        case "invalidReply":
            let callID = try container.decode(String.self, forKey: .callID)
            self = .invalidReply(callID: callID)
        case "illegalReplyType":
            let callID = try container.decode(String.self, forKey: .callID)
            let expected = try container.decode(String.self, forKey: .expected)
            let got = try container.decode(String.self, forKey: .got)
            self = .illegalReplyType(callID: callID, expected: expected, got: got)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown RemoteCallError type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .generic(let message):
            try container.encode("generic", forKey: .type)
            try container.encode(message, forKey: .message)
        case .codableError(let data, let typeName):
            try container.encode("codableError", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(typeName, forKey: .typeName)
        case .systemShutDown:
            try container.encode("systemShutDown", forKey: .type)
        case .timedOut(let callID):
            try container.encode("timedOut", forKey: .type)
            try container.encode(callID, forKey: .callID)
        case .invalidReply(let callID):
            try container.encode("invalidReply", forKey: .type)
            try container.encode(callID, forKey: .callID)
        case .illegalReplyType(let callID, let expected, let got):
            try container.encode("illegalReplyType", forKey: .type)
            try container.encode(callID, forKey: .callID)
            try container.encode(expected, forKey: .expected)
            try container.encode(got, forKey: .got)
        }
    }
}

// MARK: - CustomStringConvertible
extension RemoteCallError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .generic(let message):
            return "GenericRemoteCallError: \(message)"
        case .codableError(_, let typeName):
            return "RemoteCallError: codable error of type \(typeName)"
        case .systemShutDown:
            return "RemoteCallError: system already shut down"
        case .timedOut(let callID):
            return "RemoteCallError: call \(callID) timed out"
        case .invalidReply(let callID):
            return "RemoteCallError: invalid reply for call \(callID)"
        case .illegalReplyType(let callID, let expected, let got):
            return "RemoteCallError: illegal reply type for call \(callID), expected: \(expected), got: \(got)"
        }
    }
}

// MARK: - Error Conversion
extension RemoteCallError {
    /// Convert back to a Swift error
    public func toError() -> Error {
        switch self {
        case .generic(let message):
            // Try to parse specific ActorEdgeError cases from the message
            if message.contains("timeout") {
                return ActorEdgeError.timeout
            } else if message.contains("Actor not found") {
                return ActorEdgeError.actorNotFound(ActorEdgeID("unknown"))
            } else if message.contains("Method not found") {
                return ActorEdgeError.methodNotFound(message)
            } else if message.contains("transport") {
                return ActorEdgeError.transportError(message)
            } else if message.contains("serialization") {
                return ActorEdgeError.serializationFailed(message)
            }
            return ActorEdgeError.remoteCallFailed(self)
            
        case .codableError(let data, let typeName):
            // Try to decode the original error
            if typeName == String(reflecting: ActorEdgeError.self) {
                do {
                    return try JSONDecoder().decode(ActorEdgeError.self, from: data)
                } catch {
                    return ActorEdgeError.deserializationFailed("Failed to decode error: \(error)")
                }
            }
            return ActorEdgeError.remoteCallFailed(self)
            
        case .systemShutDown:
            return ActorEdgeError.transportError("System shut down")
            
        case .timedOut:
            return ActorEdgeError.timeout
            
        case .invalidReply, .illegalReplyType:
            return ActorEdgeError.invalidResponse
        }
    }
    
    /// Create from a Swift error (backward compatibility)
    public static func from(_ error: Error) -> RemoteCallError {
        if let actorEdgeError = error as? ActorEdgeError {
            do {
                let data = try JSONEncoder().encode(actorEdgeError)
                return .codableError(data, typeName: String(reflecting: ActorEdgeError.self))
            } catch {
                return .generic(String(describing: actorEdgeError))
            }
        }
        
        if let codableError = error as? (Error & Codable) {
            do {
                let data = try JSONEncoder().encode(AnyError(error: codableError))
                return .codableError(data, typeName: String(reflecting: type(of: codableError)))
            } catch {
                return .generic(String(describing: error))
            }
        }
        
        return .generic(String(describing: error))
    }
}

/// Helper for encoding arbitrary Codable errors
private struct AnyError: Codable {
    let description: String
    let typeName: String
    
    init<E: Error & Codable>(error: E) {
        self.description = String(describing: error)
        self.typeName = String(reflecting: type(of: error))
    }
}