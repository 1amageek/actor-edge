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
import ActorRuntime
import GRPCCore
import GRPCNIOTransportHTTP2

// Note: Using ActorRuntime.RuntimeError instead of custom ActorEdgeError

/// Factory methods for creating ActorEdgeSystem clients with different transports.
///
/// These methods provide a convenient way to create actor systems configured
/// for different transport protocols without directly dealing with transport details.
public extension ActorEdgeSystem {

    // MARK: - gRPC Transport

    /// Creates a client system with gRPC transport.
    ///
    /// This method creates a gRPC client and starts the connection management automatically.
    /// The connection will be established in the background, and the method waits for the
    /// initial connection to be ready before returning.
    ///
    /// **Connection Lifecycle**: The transport automatically manages the gRPC connection using
    /// `runConnections()` in a background task. To properly shutdown the connection:
    ///
    /// ```swift
    /// let system = try await ActorEdgeSystem.grpcClient(endpoint: "localhost:8000")
    /// // ... use the system ...
    /// try await system.shutdown()  // Gracefully close connections
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: The server endpoint in "host:port" format (e.g., "localhost:8000")
    ///   - tls: Optional TLS configuration for secure connections
    ///   - configuration: System configuration including metrics
    /// - Returns: A configured ActorEdgeSystem with active gRPC transport
    /// - Throws: RuntimeError if endpoint format is invalid or connection fails
    static func grpcClient(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil,
        configuration: Configuration = .default
    ) async throws -> ActorEdgeSystem {
        // Parse endpoint
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let host = components.first.map(String.init),
              let port = components.last.flatMap({ Int($0) }) else {
            throw RuntimeError.invalidEnvelope("Invalid endpoint format. Expected 'host:port'")
        }

        // Create HTTP/2 client transport with optional TLS
        let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity
        if let tlsConfig = tls {
            transportSecurity = try tlsConfig.toGRPCClientTransportSecurity()
        } else {
            transportSecurity = .plaintext
        }

        let clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: transportSecurity
        )

        // Create gRPC client
        let grpcClient = GRPCClient(transport: clientTransport)

        // Create GRPCTransport wrapper with automatic connection management
        // This will start runConnections() in the background
        // Connection readiness is verified on the first actual RPC call
        let transport = GRPCTransport(
            client: grpcClient,
            metricsNamespace: configuration.metrics.namespace,
            startConnections: true
        )

        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }

    // MARK: - Custom Transport

    /// Creates a client system with a custom transport implementation.
    ///
    /// - Parameters:
    ///   - transport: The custom transport implementation conforming to ActorRuntime.DistributedTransport
    ///   - configuration: System configuration including metrics
    /// - Returns: A configured ActorEdgeSystem with the custom transport
    static func client(
        transport: DistributedTransport,
        configuration: Configuration = .default
    ) -> ActorEdgeSystem {
        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }
}
