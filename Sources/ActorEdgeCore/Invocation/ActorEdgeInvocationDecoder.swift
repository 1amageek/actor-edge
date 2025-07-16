import Distributed
import Foundation

/// Decoder for distributed actor method invocations
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public struct ActorEdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = Codable & Sendable
    
    private var decoder: JSONDecoder
    private var arguments: [Data]
    private var genericSubstitutions: [String]
    private var returnTypeInfo: String?
    private var errorTypeInfo: String?
    private var currentArgumentIndex = 0
    private var currentGenericIndex = 0
    
    public init(data: Data) throws {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        let envelope = try decoder.decode(InvocationEnvelope.self, from: data)
        self.arguments = envelope.arguments
        self.genericSubstitutions = envelope.genericSubstitutions
        self.returnTypeInfo = envelope.returnType
        self.errorTypeInfo = envelope.errorType
    }
    
    /// Initialize with system and payload for server-side decoding
    public init(system: ActorEdgeSystem, payload: Data) {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        do {
            let envelope = try decoder.decode(InvocationEnvelope.self, from: payload)
            self.arguments = envelope.arguments
            self.genericSubstitutions = envelope.genericSubstitutions
            self.returnTypeInfo = envelope.returnType
            self.errorTypeInfo = envelope.errorType
        } catch {
            // If decoding fails, initialize with empty values
            self.arguments = []
            self.genericSubstitutions = []
            self.returnTypeInfo = nil
            self.errorTypeInfo = nil
        }
    }
    
    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        // Convert string type names to actual types
        return genericSubstitutions.compactMap { typeName in
            // This is a simplified implementation - in production, you'd use
            // a proper type registry or _typeByName
            return nil as Any.Type?
        }
    }
    
    public mutating func decodeNextArgument<Argument>() throws -> Argument where Argument: SerializationRequirement {
        guard currentArgumentIndex < arguments.count else {
            throw ActorEdgeError.missingArgument
        }
        
        let data = arguments[currentArgumentIndex]
        currentArgumentIndex += 1
        
        // Decode the argument directly since it conforms to Codable & Sendable
        return try decoder.decode(Argument.self, from: data)
    }
    
    public mutating func decodeReturnType() throws -> Any.Type? {
        // Return type information is stored but not used in decoding
        // It's mainly for debugging and logging purposes
        return nil
    }
    
    public mutating func decodeErrorType() throws -> Any.Type? {
        // Error type information is stored but not used in decoding
        // It's mainly for debugging and logging purposes
        return nil
    }
}

/// Container for all invocation data
private struct InvocationEnvelope: Codable {
    let arguments: [Data]
    let genericSubstitutions: [String]
    let returnType: String?
    let errorType: String?
}