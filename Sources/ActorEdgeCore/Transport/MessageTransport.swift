//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// Protocol-independent message transport layer for distributed actor communication.
///
/// This protocol abstracts the underlying transport mechanism (gRPC, TCP, etc.)
/// and provides a unified interface for sending and receiving actor messages.
///
/// Inspired by swift-distributed-actors' Wire.Envelope pattern, this design enables:
/// - Protocol independence
/// - Easy testing with in-memory implementations
/// - Runtime transport switching
/// - Clean separation of concerns
public protocol MessageTransport: Sendable {
    /// Sends an envelope and optionally waits for a response.
    ///
    /// - Parameter envelope: The message envelope to send
    /// - Returns: Optional response envelope for request-response patterns
    /// - Throws: Transport-specific errors during transmission
    func send(_ envelope: Envelope) async throws -> Envelope?
    
    /// Creates an asynchronous stream for receiving incoming envelopes.
    ///
    /// This is primarily used by server implementations to handle incoming requests.
    ///
    /// - Returns: An async stream of incoming envelopes
    func receive() -> AsyncStream<Envelope>
    
    /// Closes the transport connection and releases resources.
    ///
    /// - Throws: Transport-specific errors during shutdown
    func close() async throws
    
    /// Indicates whether the transport is currently connected.
    var isConnected: Bool { get }
    
    /// Transport-specific configuration and metadata.
    var metadata: TransportMetadata { get }
}

/// Metadata about the transport connection.
public struct TransportMetadata: Sendable {
    /// The type of transport (e.g., "grpc", "tcp")
    public let transportType: String
    
    /// Transport-specific attributes
    public let attributes: [String: String]
    
    /// Connection endpoint information
    public let endpoint: String?
    
    /// Security configuration status
    public let isSecure: Bool
    
    public init(
        transportType: String,
        attributes: [String: String] = [:],
        endpoint: String? = nil,
        isSecure: Bool = false
    ) {
        self.transportType = transportType
        self.attributes = attributes
        self.endpoint = endpoint
        self.isSecure = isSecure
    }
}

/// Transport-specific errors.
public enum TransportError: Error, Sendable {
    case connectionFailed(reason: String)
    case sendFailed(reason: String)
    case receiveFailed(reason: String)
    case timeout
    case disconnected
    case protocolMismatch(expected: String, actual: String)
    case serializationError(Error)
}