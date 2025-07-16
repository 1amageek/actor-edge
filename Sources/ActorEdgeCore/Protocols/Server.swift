import Distributed
import Foundation
import NIOSSL

/// Protocol for defining ActorEdge servers with declarative configuration
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public protocol Server {
    init()
    // MARK: - Required Configuration
    
    /// The port to listen on
    var port: Int { get }
    
    // MARK: - Optional Configuration
    
    /// The host address to bind to
    var host: String { get }
    
    /// TLS configuration for secure connections
    var tls: TLSConfiguration? { get }
    
    /// Middleware to apply to all requests
    var middleware: [any ServerMiddleware] { get }
    
    /// Maximum number of concurrent connections
    var maxConnections: Int { get }
    
    /// Request timeout duration
    var timeout: TimeInterval { get }
    
    /// Metrics collection configuration
    var metrics: MetricsConfiguration { get }
    
    /// Distributed tracing configuration
    var tracing: TracingConfiguration { get }
}

// MARK: - Default Implementations
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
public extension Server {
    var host: String { "0.0.0.0" }
    var tls: TLSConfiguration? { nil }
    var middleware: [any ServerMiddleware] { [] }
    var maxConnections: Int { 1000 }
    var timeout: TimeInterval { 30 }
    var metrics: MetricsConfiguration { .default }
    var tracing: TracingConfiguration { .default }
}