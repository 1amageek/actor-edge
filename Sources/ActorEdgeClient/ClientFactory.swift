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
    /// - Parameters:
    ///   - endpoint: The server endpoint in "host:port" format (e.g., "localhost:8000")
    ///   - tls: Optional TLS configuration for secure connections
    ///   - configuration: System configuration including metrics
    /// - Returns: A configured ActorEdgeSystem with gRPC transport
    static func grpcClient(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil,
        configuration: Configuration = .default
    ) async throws -> ActorEdgeSystem {
        print("🔷 [ClientFactory] grpcClient: Creating client for endpoint '\(endpoint)'")

        // Parse endpoint
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let host = components.first.map(String.init),
              let port = components.last.flatMap({ Int($0) }) else {
            print("🔴 [ClientFactory] grpcClient: ERROR - Invalid endpoint format")
            throw RuntimeError.invalidEnvelope("Invalid endpoint format. Expected 'host:port'")
        }

        print("🔷 [ClientFactory] grpcClient: Parsed host='\(host)', port=\(port)")

        // Create HTTP/2 client transport with optional TLS
        let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity
        if let tlsConfig = tls {
            transportSecurity = try tlsConfig.toGRPCClientTransportSecurity()
            print("🔷 [ClientFactory] grpcClient: Using TLS")
        } else {
            transportSecurity = .plaintext
            print("🔷 [ClientFactory] grpcClient: Using plaintext (no TLS)")
        }

        print("🔷 [ClientFactory] grpcClient: Creating HTTP2ClientTransport...")
        let clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: transportSecurity
        )

        print("🔷 [ClientFactory] grpcClient: Creating GRPCClient...")
        // Create gRPC client
        let grpcClient = GRPCClient(transport: clientTransport)
        print("🔷 [ClientFactory] grpcClient: GRPCClient created successfully")

        // Create GRPCTransport wrapper with metrics namespace
        let transport = GRPCTransport(
            client: grpcClient,
            metricsNamespace: configuration.metrics.namespace
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
