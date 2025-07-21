//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import Foundation

/// Simplified server configuration combining all settings
public struct ServerConfiguration: Sendable {
    /// Network settings
    public let host: String
    public let port: Int
    
    /// TLS configuration
    public let tls: TLSConfiguration?
    
    /// Performance settings
    public let maxConnections: Int
    public let timeout: TimeInterval
    
    /// Monitoring settings
    public let metricsEnabled: Bool
    public let metricsNamespace: String
    public let tracingEnabled: Bool
    public let tracingServiceName: String
    
    public init(
        host: String = "127.0.0.1",
        port: Int = 8000,
        tls: TLSConfiguration? = nil,
        maxConnections: Int = 1000,
        timeout: TimeInterval = 30,
        metricsEnabled: Bool = true,
        metricsNamespace: String = "actor_edge",
        tracingEnabled: Bool = true,
        tracingServiceName: String = "actor-edge-server"
    ) {
        self.host = host
        self.port = port
        self.tls = tls
        self.maxConnections = maxConnections
        self.timeout = timeout
        self.metricsEnabled = metricsEnabled
        self.metricsNamespace = metricsNamespace
        self.tracingEnabled = tracingEnabled
        self.tracingServiceName = tracingServiceName
    }
    
    /// Default configuration for development
    public static let development = ServerConfiguration()
    
    /// Production configuration with TLS enabled
    public static func production(
        certificatePath: String,
        privateKeyPath: String,
        host: String = "0.0.0.0",
        port: Int = 443
    ) throws -> ServerConfiguration {
        let tls = try TLSConfiguration.fromFiles(
            certificatePath: certificatePath,
            privateKeyPath: privateKeyPath
        )
        
        return ServerConfiguration(
            host: host,
            port: port,
            tls: tls,
            maxConnections: 10000,
            timeout: 60
        )
    }
}