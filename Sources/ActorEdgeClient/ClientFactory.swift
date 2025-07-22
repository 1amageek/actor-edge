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
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A configured ActorEdgeSystem with gRPC transport
    static func grpcClient(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil,
        configuration: Configuration = .default
    ) async throws -> ActorEdgeSystem {
        let transport = try await GRPCMessageTransport(
            endpoint: endpoint,
            tls: tls,
            configuration: configuration
        )
        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }
    
    
    // MARK: - In-Memory Transport
    
    /// Creates a client system with in-memory transport for testing.
    ///
    /// - Parameters:
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A tuple containing the client system and its transport
    static func inMemoryClient(
        configuration: Configuration = .default
    ) -> (system: ActorEdgeSystem, transport: InMemoryMessageTransport) {
        let transport = InMemoryMessageTransport()
        let system = ActorEdgeSystem(transport: transport, configuration: configuration)
        return (system, transport)
    }
    
    /// Creates a pair of connected client and server systems for testing.
    ///
    /// - Parameter configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A tuple containing connected client and server systems
    static func createConnectedPair(
        configuration: Configuration = .default
    ) -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let client = ActorEdgeSystem(transport: clientTransport, configuration: configuration)
        let server = ActorEdgeSystem(configuration: configuration)
        
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
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A configured ActorEdgeSystem with the custom transport
    static func client(
        transport: MessageTransport,
        configuration: Configuration = .default
    ) -> ActorEdgeSystem {
        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }
}

// MARK: - Connection Helpers

public extension ActorEdgeSystem {
    /// Connects to a server using the most appropriate transport based on the URL scheme.
    ///
    /// Supported schemes:
    /// - `grpc://` or `grpcs://` for gRPC transport
    ///
    /// - Parameters:
    ///   - url: The server URL with scheme
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A configured ActorEdgeSystem
    static func connect(
        to url: URL,
        configuration: Configuration = .default
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
                configuration: configuration
            )
            
        default:
            throw TransportError.protocolMismatch(
                expected: "grpc or grpcs",
                actual: scheme
            )
        }
    }
}

