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
    case remoteCall(InvocationData)
    
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
    func writeError(_ error: SerializedError) async throws
}

/// Response writer implementation for envelope-based responses
public struct EnvelopeResponseWriter: ResponseWriter {
    private let callID: String
    private let recipient: ActorEdgeID
    private let sender: ActorEdgeID?
    private let writeEnvelope: @Sendable (Envelope) async throws -> Void
    
    public init(
        callID: String,
        recipient: ActorEdgeID,
        sender: ActorEdgeID? = nil,
        writeEnvelope: @escaping @Sendable (Envelope) async throws -> Void
    ) {
        self.callID = callID
        self.recipient = recipient
        self.sender = sender
        self.writeEnvelope = writeEnvelope
    }
    
    public func writeSuccess(_ data: Data) async throws {
        print("🔵 [DEBUG] EnvelopeResponseWriter.writeSuccess called, dataSize: \(data.count)")
        
        let responseData = ResponseData(result: .success(data))
        let payload = try JSONEncoder().encode(responseData)
        
        let envelope = Envelope.response(
            to: recipient,
            from: sender,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json", hint: "ResponseData"),
            payload: payload
        )
        
        print("🔵 [DEBUG] Writing success response envelope")
        try await writeEnvelope(envelope)
        print("🟢 [DEBUG] Success response written")
    }
    
    public func writeVoid() async throws {
        print("🔵 [DEBUG] EnvelopeResponseWriter.writeVoid called")
        
        let responseData = ResponseData(result: .void)
        let payload = try JSONEncoder().encode(responseData)
        
        let envelope = Envelope.response(
            to: recipient,
            from: sender,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json", hint: "ResponseData"),
            payload: payload
        )
        
        print("🔵 [DEBUG] Writing void response envelope")
        try await writeEnvelope(envelope)
        print("🟢 [DEBUG] Void response written")
    }
    
    public func writeError(_ error: SerializedError) async throws {
        print("🔴 [DEBUG] EnvelopeResponseWriter.writeError called: \(error)")
        
        let responseData = ResponseData(result: .error(error))
        let payload = try JSONEncoder().encode(responseData)
        
        let envelope = Envelope.error(
            to: recipient,
            from: sender,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json", hint: "ResponseData"),
            payload: payload
        )
        
        print("🔴 [DEBUG] Writing error response envelope")
        try await writeEnvelope(envelope)
        print("🔴 [DEBUG] Error response written")
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

/// Response writer that signals completion after writing
public struct CompletingResponseWriter: ResponseWriter {
    private let base: any ResponseWriter
    private let continuation: AsyncStream<Void>.Continuation
    
    public init(base: any ResponseWriter, continuation: AsyncStream<Void>.Continuation) {
        self.base = base
        self.continuation = continuation
    }
    
    public func writeSuccess(_ data: Data) async throws {
        print("🔵 [DEBUG] CompletingResponseWriter.writeSuccess called")
        try await base.writeSuccess(data)
        print("🔵 [DEBUG] CompletingResponseWriter signaling completion")
        continuation.yield(())
        continuation.finish()
    }
    
    public func writeVoid() async throws {
        print("🔵 [DEBUG] CompletingResponseWriter.writeVoid called")
        try await base.writeVoid()
        print("🔵 [DEBUG] CompletingResponseWriter signaling completion")
        continuation.yield(())
        continuation.finish()
    }
    
    public func writeError(_ error: SerializedError) async throws {
        print("🔴 [DEBUG] CompletingResponseWriter.writeError called")
        try await base.writeError(error)
        print("🔴 [DEBUG] CompletingResponseWriter signaling completion")
        continuation.yield(())
        continuation.finish()
    }
}