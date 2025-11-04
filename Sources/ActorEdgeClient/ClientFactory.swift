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
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A configured ActorEdgeSystem with gRPC transport
    static func grpcClient(
        endpoint: String,
        configuration: Configuration = .default
    ) async throws -> ActorEdgeSystem {
        // Parse endpoint
        let components = endpoint.split(separator: ":")
        guard components.count == 2,
              let host = components.first.map(String.init),
              let port = components.last.flatMap({ Int($0) }) else {
            throw RuntimeError.invalidEnvelope("Invalid endpoint format. Expected 'host:port'")
        }

        // Create HTTP/2 client transport
        let clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: .plaintext
        )

        // Create gRPC client
        let grpcClient = GRPCClient(transport: clientTransport)

        // Create GRPCTransport wrapper
        let transport = GRPCTransport(client: grpcClient)

        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }

    // MARK: - Custom Transport

    /// Creates a client system with a custom transport implementation.
    ///
    /// - Parameters:
    ///   - transport: The custom transport implementation conforming to ActorRuntime.DistributedTransport
    ///   - configuration: System configuration including metrics, tracing, etc.
    /// - Returns: A configured ActorEdgeSystem with the custom transport
    static func client(
        transport: DistributedTransport,
        configuration: Configuration = .default
    ) -> ActorEdgeSystem {
        return ActorEdgeSystem(transport: transport, configuration: configuration)
    }
}
