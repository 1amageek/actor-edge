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
import ActorEdgeCore

/// Factory methods for creating ActorEdgeSystem clients with different transports.
///
/// These methods provide a convenient way to create actor systems configured
/// for different transport protocols without directly dealing with transport details.
public extension ActorEdgeSystem {
    
    // MARK: - gRPC Transport
    
    /// Creates a client system with gRPC transport.
    ///
    /// - Parameters:
    ///   - endpoint: The server endpoint in "host:port" format
    ///   - tls: Optional TLS configuration for secure connections
    ///   - metricsNamespace: Namespace for metrics collection
    /// - Returns: A configured ActorEdgeSystem with gRPC transport
    static func grpcClient(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil,
        metricsNamespace: String = "actor_edge"
    ) async throws -> ActorEdgeSystem {
        let transport = try await GRPCMessageTransport(
            endpoint: endpoint,
            tls: tls,
            metricsNamespace: metricsNamespace
        )
        return ActorEdgeSystem(transport: transport, metricsNamespace: metricsNamespace)
    }
    
    // MARK: - WebSocket Transport (Future)
    
    /// Creates a client system with WebSocket transport.
    ///
    /// - Parameters:
    ///   - url: The WebSocket URL
    ///   - headers: Optional HTTP headers for the WebSocket handshake
    ///   - metricsNamespace: Namespace for metrics collection
    /// - Returns: A configured ActorEdgeSystem with WebSocket transport
    @available(*, unavailable, message: "WebSocket transport not yet implemented")
    static func webSocketClient(
        url: URL,
        headers: [String: String] = [:],
        metricsNamespace: String = "actor_edge"
    ) async throws -> ActorEdgeSystem {
        fatalError("WebSocket transport not yet implemented")
        // Future implementation:
        // let transport = try await WebSocketMessageTransport(url: url, headers: headers)
        // return ActorEdgeSystem(transport: transport, metricsNamespace: metricsNamespace)
    }
    
    // MARK: - In-Memory Transport
    
    /// Creates a client system with in-memory transport for testing.
    ///
    /// - Parameters:
    ///   - metricsNamespace: Namespace for metrics collection
    /// - Returns: A tuple containing the client system and its transport
    static func inMemoryClient(
        metricsNamespace: String = "actor_edge"
    ) -> (system: ActorEdgeSystem, transport: InMemoryMessageTransport) {
        let transport = InMemoryMessageTransport()
        let system = ActorEdgeSystem(transport: transport, metricsNamespace: metricsNamespace)
        return (system, transport)
    }
    
    /// Creates a pair of connected client and server systems for testing.
    ///
    /// - Parameter metricsNamespace: Namespace for metrics collection
    /// - Returns: A tuple containing connected client and server systems
    static func createConnectedPair(
        metricsNamespace: String = "actor_edge"
    ) -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let client = ActorEdgeSystem(transport: clientTransport, metricsNamespace: metricsNamespace)
        let server = ActorEdgeSystem(metricsNamespace: metricsNamespace)
        
        // Set up server transport to handle invocations
        serverTransport.setMessageHandler { envelope in
            // This would be handled by ActorEdgeServer in production
            // For testing, we can simulate server behavior here
            return nil
        }
        
        return (client, server)
    }
    
    // MARK: - Custom Transport
    
    /// Creates a client system with a custom transport implementation.
    ///
    /// - Parameters:
    ///   - transport: The custom transport implementation
    ///   - metricsNamespace: Namespace for metrics collection
    /// - Returns: A configured ActorEdgeSystem with the custom transport
    static func client(
        transport: MessageTransport,
        metricsNamespace: String = "actor_edge"
    ) -> ActorEdgeSystem {
        return ActorEdgeSystem(transport: transport, metricsNamespace: metricsNamespace)
    }
}

// MARK: - Connection Helpers

public extension ActorEdgeSystem {
    /// Connects to a server using the most appropriate transport based on the URL scheme.
    ///
    /// Supported schemes:
    /// - `grpc://` or `grpcs://` for gRPC transport
    /// - `ws://` or `wss://` for WebSocket transport (future)
    /// - `tcp://` for raw TCP transport (future)
    ///
    /// - Parameters:
    ///   - url: The server URL with scheme
    ///   - options: Connection options
    /// - Returns: A configured ActorEdgeSystem
    static func connect(
        to url: URL,
        options: ConnectionOptions = .defaults
    ) async throws -> ActorEdgeSystem {
        guard let scheme = url.scheme?.lowercased() else {
            throw TransportError.protocolMismatch(
                expected: "URL with scheme",
                actual: "no scheme"
            )
        }
        
        switch scheme {
        case "grpc", "grpcs":
            let endpoint = "\(url.host ?? "localhost"):\(url.port ?? 443)"
            let tls: ClientTLSConfiguration? = scheme == "grpcs" ? .systemDefault() : nil
            return try await grpcClient(
                endpoint: endpoint,
                tls: tls,
                metricsNamespace: options.metricsNamespace
            )
            
        case "ws", "wss":
            throw TransportError.protocolMismatch(
                expected: "supported protocol",
                actual: "WebSocket (not yet implemented)"
            )
            
        default:
            throw TransportError.protocolMismatch(
                expected: "grpc, grpcs, ws, or wss",
                actual: scheme
            )
        }
    }
}

/// Options for establishing connections.
public struct ConnectionOptions: Sendable {
    /// Namespace for metrics collection
    public let metricsNamespace: String
    
    /// Request timeout
    public let timeout: TimeInterval
    
    /// Maximum retry attempts
    public let maxRetries: Int
    
    /// Custom headers
    public let headers: [String: String]
    
    public init(
        metricsNamespace: String = "actor_edge",
        timeout: TimeInterval = 30,
        maxRetries: Int = 3,
        headers: [String: String] = [:]
    ) {
        self.metricsNamespace = metricsNamespace
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.headers = headers
    }
    
    /// Default connection options
    public static let defaults = ConnectionOptions()
}