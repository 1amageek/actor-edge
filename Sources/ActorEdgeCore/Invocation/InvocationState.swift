import Foundation
import Distributed
import SwiftProtobuf

/// State management for invocation encoding
/// Based on swift-distributed-actors patterns
public enum InvocationEncoderState {
    /// Recording arguments for a new invocation
    case recording
    
    /// Encoding completed, ready for transmission
    case completed
}

/// State management for invocation decoding  
/// Based on swift-distributed-actors ClusterInvocationDecoder state patterns
public enum InvocationDecoderState {
    /// Decoding from a remote call message
    case remoteCall(InvocationMessage)
    
    /// Decoding from a local call (proxy optimization)
    case localCall(ActorEdgeInvocationEncoder)
}

/// State management for result handling
/// Based on swift-distributed-actors ClusterInvocationResultHandler state patterns
public enum ResultHandlerState {
    /// Handling result for a local direct call with continuation
    case localDirectReturn(CheckedContinuation<Any, Error>)
    
    /// Handling result for a remote call that needs network response
    case remoteCall(
        system: ActorEdgeSystem,
        callID: String,
        responseWriter: any ResponseWriter
    )
}

/// Protocol for writing responses back to remote callers
public protocol ResponseWriter: Sendable {
    /// Write a successful response
    func writeSuccess(_ data: Data) async throws
    
    /// Write a void response
    func writeVoid() async throws
    
    /// Write an error response
    func writeError(_ error: RemoteCallError) async throws
}

/// Response writer implementation for gRPC streaming responses
public struct GRPCResponseWriter: ResponseWriter {
    private let callID: String
    private let writeResponse: @Sendable (Actoredge_RemoteCallResponse) async throws -> Void
    
    public init(callID: String, writeResponse: @escaping @Sendable (Actoredge_RemoteCallResponse) async throws -> Void) {
        self.callID = callID
        self.writeResponse = writeResponse
    }
    
    public func writeSuccess(_ data: Data) async throws {
        let response = Actoredge_RemoteCallResponse.with {
            $0.callID = callID
            $0.value = data
        }
        try await writeResponse(response)
    }
    
    public func writeVoid() async throws {
        // For void returns, send empty data
        let response = Actoredge_RemoteCallResponse.with {
            $0.callID = callID
            $0.value = Data()
        }
        try await writeResponse(response)
    }
    
    public func writeError(_ error: RemoteCallError) async throws {
        let errorEnvelope = createErrorEnvelope(from: error)
        let response = Actoredge_RemoteCallResponse.with {
            $0.callID = callID
            $0.error = errorEnvelope
        }
        try await writeResponse(response)
    }
    
    private func createErrorEnvelope(from error: RemoteCallError) -> Actoredge_ErrorEnvelope {
        switch error {
        case .generic(let message):
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "RemoteCallError.generic"
                $0.data = Data(message.utf8)
                $0.description_p = message
            }
        case .codableError(let data, let typeName):
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = typeName
                $0.data = data
                $0.description_p = "Codable error of type \(typeName)"
            }
        case .timedOut(let callID):
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "RemoteCallError.timedOut"
                $0.data = Data(callID.utf8)
                $0.description_p = "Call timed out: \(callID)"
            }
        case .systemShutDown:
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "RemoteCallError.systemShutDown"
                $0.data = Data()
                $0.description_p = "System is shutting down"
            }
        case .invalidReply(let callID):
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "RemoteCallError.invalidReply"
                $0.data = Data(callID.utf8)
                $0.description_p = "Invalid reply for call: \(callID)"
            }
        case .illegalReplyType(let callID, let expected, let got):
            let errorData = "\(callID)|\(expected)|\(got)"
            return Actoredge_ErrorEnvelope.with {
                $0.typeURL = "RemoteCallError.illegalReplyType"
                $0.data = Data(errorData.utf8)
                $0.description_p = "Illegal reply type for call \(callID), expected: \(expected), got: \(got)"
            }
        }
    }
}

/// Type-erased async writer protocol
public protocol AsyncWriter: Sendable {
    associatedtype Element
    func write(_ element: Element) async throws
}

/// Call ID generator for unique remote call identification
public struct CallIDGenerator {
    public static func generate() -> String {
        UUID().uuidString
    }
    
    public static func generate(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString)"
    }
}

/// Metadata keys for distributed actor context
public extension CodingUserInfoKey {
    /// Key for storing serialization context
    static let serializationContextKey = CodingUserInfoKey(rawValue: "SerializationContext")!
}