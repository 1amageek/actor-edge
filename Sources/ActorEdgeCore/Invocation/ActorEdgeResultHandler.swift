import Distributed
import Foundation

/// Handler for distributed actor method results
/// Based on swift-distributed-actors ClusterInvocationResultHandler patterns
public final class ActorEdgeResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State (following swift-distributed-actors pattern)
    
    /// Current handler state
    private let state: ResultHandlerState
    
    /// JSON encoder for result serialization
    private let encoder: JSONEncoder
    
    // MARK: - Initialization
    
    /// Initialize for local direct return (with continuation)
    public init(continuation: CheckedContinuation<Any, Error>) {
        self.state = .localDirectReturn(continuation)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }
    
    /// Initialize for remote call (with response writer)
    public init(
        system: ActorEdgeSystem,
        callID: String,
        responseWriter: any ResponseWriter
    ) {
        self.state = .remoteCall(
            system: system,
            callID: callID,
            responseWriter: responseWriter
        )
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }
    
    /// Legacy initialization for backward compatibility
    /// This will be phased out once all usage is updated
    public init() {
        // Use a special legacy state that doesn't depend on CheckedContinuation
        // This is only for backward compatibility
        self.state = .legacyMode
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.sortedKeys]
    }
    
    // MARK: - DistributedTargetInvocationResultHandler Implementation
    // Following swift-distributed-actors state-based pattern
    
    public func onReturn<Success>(
        value: Success
    ) async throws where Success: SerializationRequirement {
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume the continuation with the value
            continuation.resume(returning: value)
            
        case .remoteCall(let system, let callID, let responseWriter):
            // For remote calls, serialize and send back over network
            do {
                let valueData = try encoder.encode(value)
                try await responseWriter.writeSuccess(valueData)
            } catch {
                // If serialization fails, send error instead
                let remoteError = RemoteCallError.codableError(
                    try encoder.encode("Serialization failed: \(error)"),
                    typeName: "SerializationError"
                )
                try await responseWriter.writeError(remoteError)
            }
            
        case .legacyMode:
            // For legacy mode, store the data internally
            let valueData = try encoder.encode(value)
            storeResultData(valueData)
        }
    }
    
    public func onReturnVoid() async throws {
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume with empty tuple (Swift's representation of void)
            continuation.resume(returning: ())
            
        case .remoteCall(let system, let callID, let responseWriter):
            // For remote calls, send void return marker
            try await responseWriter.writeVoid()
            
        case .legacyMode:
            // For legacy mode, store empty data for void return
            storeResultData(Data())
        }
    }
    
    public func onThrow<Err: Error>(
        error: Err
    ) async throws {
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume by throwing the error
            continuation.resume(throwing: error)
            
        case .remoteCall(let system, let callID, let responseWriter):
            // For remote calls, serialize and send error
            let remoteError = serializeError(error)
            try await responseWriter.writeError(remoteError)
            
        case .legacyMode:
            // For legacy mode, re-throw the error (will be handled by caller)
            throw error
        }
    }
    
    // MARK: - Error Serialization (following swift-distributed-actors pattern)
    
    /// Serialize an error for transmission over network
    /// Based on swift-distributed-actors error handling patterns
    private func serializeError<Err: Error>(_ error: Err) -> RemoteCallError {
        // Handle ActorEdge specific errors
        if let actorEdgeError = error as? ActorEdgeError {
            do {
                let errorData = try encoder.encode(actorEdgeError)
                return .codableError(
                    errorData,
                    typeName: String(reflecting: ActorEdgeError.self)
                )
            } catch {
                return .generic("Failed to serialize ActorEdgeError: \(error)")
            }
        }
        
        // Handle general Codable errors
        if let codableError = error as? (Error & Codable) {
            do {
                let errorData = try encoder.encode(AnyError(error: codableError))
                return .codableError(
                    errorData,
                    typeName: String(reflecting: type(of: codableError))
                )
            } catch {
                return .generic("Failed to serialize codable error: \(error)")
            }
        }
        
        // For non-codable errors, create generic error
        return .generic(String(describing: error))
    }
    
    // MARK: - Legacy Support
    
    /// Captured result data for legacy compatibility
    private var capturedData: Data?
    
    /// Get the result data (legacy method for backward compatibility)
    /// This will be removed once all usage is updated to proper state-based handling
    public func getResultData() -> Data {
        return capturedData ?? Data()
    }
    
    /// Store result data for legacy compatibility
    internal func storeResultData(_ data: Data) {
        self.capturedData = data
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

// MARK: - Factory Methods (following swift-distributed-actors patterns)

extension ActorEdgeResultHandler {
    
    /// Create a result handler for local direct returns
    public static func forLocalReturn(
        continuation: CheckedContinuation<Any, Error>
    ) -> ActorEdgeResultHandler {
        return ActorEdgeResultHandler(continuation: continuation)
    }
    
    /// Create a result handler for remote calls
    public static func forRemoteCall(
        system: ActorEdgeSystem,
        callID: String,
        responseWriter: any ResponseWriter
    ) -> ActorEdgeResultHandler {
        return ActorEdgeResultHandler(
            system: system,
            callID: callID,
            responseWriter: responseWriter
        )
    }
    
    /// Legacy factory method for backward compatibility
    public static func createHandler() -> ActorEdgeResultHandler {
        return ActorEdgeResultHandler()
    }
}