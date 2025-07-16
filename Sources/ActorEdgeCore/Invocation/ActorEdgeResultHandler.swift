import Distributed
import Foundation

/// Handler for distributed actor method results
public final class ActorEdgeResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable & Sendable
    
    private let encoder = JSONEncoder()
    
    public init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }
    
    // Store the result data for later retrieval
    private var resultData: Data?
    
    public func onReturn<Success>(
        value: Success
    ) async throws where Success: SerializationRequirement {
        // Note: The protocol expects void return, but we need to capture the data
        // This is a limitation of the current design - we'll need to store it
        resultData = try encoder.encode(value)
    }
    
    public func onReturnVoid() async throws {
        // Return empty data for void returns
        resultData = Data()
    }
    
    public func onThrow<Err: Error>(
        error: Err
    ) async throws {
        // For ActorEdge errors, encode directly
        if let actorEdgeError = error as? ActorEdgeError {
            let envelope = ErrorEnvelope(
                typeURL: String(reflecting: ActorEdgeError.self),
                data: try encoder.encode(actorEdgeError)
            )
            throw ActorEdgeError.remoteError(envelope)
        }
        
        // For Codable errors, encode them
        if let codableError = error as? (Error & Codable) {
            let envelope = ErrorEnvelope(
                typeURL: String(reflecting: type(of: error)),
                data: try encoder.encode(codableError)
            )
            throw ActorEdgeError.remoteError(envelope)
        }
        
        // For non-codable errors, create a transport error
        throw ActorEdgeError.transportError(String(describing: error))
    }
    
    /// Get the result data after execution
    public func getResultData() -> Data {
        resultData ?? Data()
    }
}

// Extension to make ActorEdgeResultHandler mutable for data storage
extension ActorEdgeResultHandler {
    /// Create a result handler that can capture data
    public static func createHandler() -> ActorEdgeResultHandler {
        ActorEdgeResultHandler()
    }
}