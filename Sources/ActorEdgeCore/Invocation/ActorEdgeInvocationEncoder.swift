import Distributed
import Foundation

/// Encoder for distributed actor method invocations
public struct ActorEdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    private var encoder: JSONEncoder
    private var arguments: [Data] = []
    private var genericSubstitutions: [String] = []
    private var returnTypeInfo: String?
    private var errorTypeInfo: String?
    
    public init() {
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        genericSubstitutions.append(String(reflecting: type))
    }
    
    public mutating func recordArgument<Argument>(
        _ argument: RemoteCallArgument<Argument>
    ) throws where Argument: SerializationRequirement {
        let data = try encoder.encode(argument.value)
        arguments.append(data)
    }
    
    public mutating func recordReturnType<R>(
        _ returnType: R.Type
    ) throws where R: SerializationRequirement {
        returnTypeInfo = String(reflecting: returnType)
    }
    
    public mutating func recordErrorType<E: Error>(_ errorType: E.Type) throws {
        errorTypeInfo = String(reflecting: errorType)
    }
    
    public mutating func doneRecording() throws {
        // Protocol expects void, but we need to return data
        // This is handled through a separate method
    }
    
    /// Get the encoded data after recording is done
    public func getEncodedData() throws -> Data {
        let envelope = InvocationEnvelope(
            arguments: arguments,
            genericSubstitutions: genericSubstitutions,
            returnType: returnTypeInfo,
            errorType: errorTypeInfo
        )
        return try encoder.encode(envelope)
    }
}

/// Container for all invocation data
private struct InvocationEnvelope: Codable {
    let arguments: [Data]
    let genericSubstitutions: [String]
    let returnType: String?
    let errorType: String?
}