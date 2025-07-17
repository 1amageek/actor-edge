import Foundation
import Distributed

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
    
    /// Legacy mode for backward compatibility (stores data internally)
    case legacyMode
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
    private let writeFunction: @Sendable (Data) async throws -> Void
    
    public init<W: AsyncWriter>(writer: W) where W.Element == Data {
        self.writeFunction = { data in
            try await writer.write(data)
        }
    }
    
    public func writeSuccess(_ data: Data) async throws {
        // For now, write the data directly - reply wrapping will be handled later
        try await writeFunction(data)
    }
    
    public func writeVoid() async throws {
        let voidData = try JSONEncoder().encode(VoidReturn())
        try await writeFunction(voidData)
    }
    
    public func writeError(_ error: RemoteCallError) async throws {
        let errorData = try JSONEncoder().encode(error)
        try await writeFunction(errorData)
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
    /// Key for storing the ActorEdgeSystem in decoder userInfo
    /// Required for distributed actor argument deserialization
    static let actorSystemKey = CodingUserInfoKey(rawValue: "ActorEdgeSystem")!
    
    /// Key for storing serialization context
    static let serializationContextKey = CodingUserInfoKey(rawValue: "SerializationContext")!
}