import Foundation

/// Errors that can occur in the ActorEdge system
public enum ActorEdgeError: Error, Codable, Sendable {
    case actorNotFound(ActorEdgeID)
    case actorTypeMismatch(ActorEdgeID, expected: String, actual: String)
    case methodNotFound(String)
    case serializationFailed(String)
    case deserializationFailed(String)
    case transportError(String)
    case timeout
    case unauthorized
    case remoteError(ErrorEnvelope)
    case invalidResponse
    case missingArgument
    case invalidFormat(String)
    case invocationError(String)
    case remoteCallError(String)
    case invalidEnvelope(String)
    case connectionRejected(reason: String)
    case protocolMismatch(String)
    case typeMismatch(expected: String, actual: String)
    case typeNotFound(String)
    
    private enum CodingKeys: String, CodingKey {
        case type
        case actorID
        case expectedType
        case actualType
        case method
        case message
        case errorEnvelope
        case reason
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "actorNotFound":
            let actorID = try container.decode(ActorEdgeID.self, forKey: .actorID)
            self = .actorNotFound(actorID)
        case "actorTypeMismatch":
            let actorID = try container.decode(ActorEdgeID.self, forKey: .actorID)
            let expectedType = try container.decode(String.self, forKey: .expectedType)
            let actualType = try container.decode(String.self, forKey: .actualType)
            self = .actorTypeMismatch(actorID, expected: expectedType, actual: actualType)
        case "methodNotFound":
            let method = try container.decode(String.self, forKey: .method)
            self = .methodNotFound(method)
        case "serializationFailed":
            let message = try container.decode(String.self, forKey: .message)
            self = .serializationFailed(message)
        case "deserializationFailed":
            let message = try container.decode(String.self, forKey: .message)
            self = .deserializationFailed(message)
        case "transportError":
            let message = try container.decode(String.self, forKey: .message)
            self = .transportError(message)
        case "timeout":
            self = .timeout
        case "unauthorized":
            self = .unauthorized
        case "remoteError":
            let envelope = try container.decode(ErrorEnvelope.self, forKey: .errorEnvelope)
            self = .remoteError(envelope)
        case "invalidResponse":
            self = .invalidResponse
        case "missingArgument":
            self = .missingArgument
        case "invalidFormat":
            let message = try container.decode(String.self, forKey: .message)
            self = .invalidFormat(message)
        case "invocationError":
            let message = try container.decode(String.self, forKey: .message)
            self = .invocationError(message)
        case "remoteCallError":
            let message = try container.decode(String.self, forKey: .message)
            self = .remoteCallError(message)
        case "invalidEnvelope":
            let message = try container.decode(String.self, forKey: .message)
            self = .invalidEnvelope(message)
        case "connectionRejected":
            let reason = try container.decode(String.self, forKey: .reason)
            self = .connectionRejected(reason: reason)
        case "protocolMismatch":
            let message = try container.decode(String.self, forKey: .message)
            self = .protocolMismatch(message)
        case "typeMismatch":
            let expectedType = try container.decode(String.self, forKey: .expectedType)
            let actualType = try container.decode(String.self, forKey: .actualType)
            self = .typeMismatch(expected: expectedType, actual: actualType)
        case "typeNotFound":
            let message = try container.decode(String.self, forKey: .message)
            self = .typeNotFound(message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown error type: \(type)"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .actorNotFound(let actorID):
            try container.encode("actorNotFound", forKey: .type)
            try container.encode(actorID, forKey: .actorID)
        case .actorTypeMismatch(let actorID, let expectedType, let actualType):
            try container.encode("actorTypeMismatch", forKey: .type)
            try container.encode(actorID, forKey: .actorID)
            try container.encode(expectedType, forKey: .expectedType)
            try container.encode(actualType, forKey: .actualType)
        case .methodNotFound(let method):
            try container.encode("methodNotFound", forKey: .type)
            try container.encode(method, forKey: .method)
        case .serializationFailed(let message):
            try container.encode("serializationFailed", forKey: .type)
            try container.encode(message, forKey: .message)
        case .deserializationFailed(let message):
            try container.encode("deserializationFailed", forKey: .type)
            try container.encode(message, forKey: .message)
        case .transportError(let message):
            try container.encode("transportError", forKey: .type)
            try container.encode(message, forKey: .message)
        case .timeout:
            try container.encode("timeout", forKey: .type)
        case .unauthorized:
            try container.encode("unauthorized", forKey: .type)
        case .remoteError(let envelope):
            try container.encode("remoteError", forKey: .type)
            try container.encode(envelope, forKey: .errorEnvelope)
        case .invalidResponse:
            try container.encode("invalidResponse", forKey: .type)
        case .missingArgument:
            try container.encode("missingArgument", forKey: .type)
        case .invalidFormat(let message):
            try container.encode("invalidFormat", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invocationError(let message):
            try container.encode("invocationError", forKey: .type)
            try container.encode(message, forKey: .message)
        case .remoteCallError(let message):
            try container.encode("remoteCallError", forKey: .type)
            try container.encode(message, forKey: .message)
        case .invalidEnvelope(let message):
            try container.encode("invalidEnvelope", forKey: .type)
            try container.encode(message, forKey: .message)
        case .connectionRejected(let reason):
            try container.encode("connectionRejected", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .protocolMismatch(let message):
            try container.encode("protocolMismatch", forKey: .type)
            try container.encode(message, forKey: .message)
        case .typeMismatch(let expectedType, let actualType):
            try container.encode("typeMismatch", forKey: .type)
            try container.encode(expectedType, forKey: .expectedType)
            try container.encode(actualType, forKey: .actualType)
        case .typeNotFound(let message):
            try container.encode("typeNotFound", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}

/// Envelope for transmitting errors over the network
public struct ErrorEnvelope: Codable, Sendable {
    public let typeURL: String
    public let data: Data
    
    public init(typeURL: String, data: Data) {
        self.typeURL = typeURL
        self.data = data
    }
    
    public func toError() throws -> Error {
        switch typeURL {
        case String(reflecting: ActorEdgeError.self):
            return try JSONDecoder().decode(ActorEdgeError.self, from: data)
        default:
            return RemoteError(typeURL: typeURL, data: data)
        }
    }
}

/// A remote error that couldn't be decoded to a known type
public struct RemoteError: Error {
    public let typeURL: String
    public let data: Data
    
    public init(typeURL: String, data: Data) {
        self.typeURL = typeURL
        self.data = data
    }
}