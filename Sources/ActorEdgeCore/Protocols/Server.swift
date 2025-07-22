import Distributed
import Foundation
import NIOSSL

/// Result builder for creating distributed actors in a declarative way
@resultBuilder
public struct ActorBuilder {
    
    /// Build a block of actors from components
    public static func buildBlock(_ components: [any DistributedActor]...) -> [any DistributedActor] {
        components.flatMap { $0 }
    }
    
    /// Build empty block
    public static func buildBlock() -> [any DistributedActor] {
        []
    }
    
    /// Build from a single actor
    public static func buildExpression(_ actor: any DistributedActor) -> [any DistributedActor] {
        [actor]
    }
    
    /// Build from an array of actors
    public static func buildExpression(_ actors: [any DistributedActor]) -> [any DistributedActor] {
        actors
    }
    
    /// Build from void/empty
    public static func buildExpression(_ value: ()) -> [any DistributedActor] {
        []
    }
    
    /// Build optional actors
    public static func buildOptional(_ component: [any DistributedActor]?) -> [any DistributedActor] {
        component ?? []
    }
    
    /// Build conditional actors (if-else)
    public static func buildEither(first: [any DistributedActor]) -> [any DistributedActor] {
        first
    }
    
    /// Build conditional actors (if-else)
    public static func buildEither(second: [any DistributedActor]) -> [any DistributedActor] {
        second
    }
    
    /// Build arrays of actors
    public static func buildArray(_ components: [[any DistributedActor]]) -> [any DistributedActor] {
        components.flatMap { $0 }
    }
    
    /// Build limited availability actors
    public static func buildLimitedAvailability(_ component: [any DistributedActor]) -> [any DistributedActor] {
        component
    }
}

// MARK: - Server Protocol

/// Protocol for defining ActorEdge servers with declarative configuration
public protocol Server: Sendable {
    init()
    
    // MARK: - Actor Configuration
    
    /// Define the distributed actors managed by this server
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor]
    
    /// Provides well-known IDs for actors (optional)
    /// If not implemented, actors will be assigned IDs like "actor-0", "actor-1", etc.
    var actorIDs: [String] { get }
    
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
    
    /// Maximum retry attempts
    var maxRetries: Int { get }
    
    /// Metrics collection configuration
    var metrics: MetricsConfiguration { get }
    
    /// Distributed tracing configuration
    var tracing: TracingConfiguration { get }
}

// MARK: - Default Implementations
public extension Server {
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        []
    }
    
    var actorIDs: [String] { [] }
    var port: Int { 8000 }
    var host: String { "127.0.0.1" }
    var tls: TLSConfiguration? { nil }
    var middleware: [any ServerMiddleware] { [] }
    var maxConnections: Int { 1000 }
    var timeout: TimeInterval { 30 }
    var maxRetries: Int { 3 }
    var metrics: MetricsConfiguration { .default }
    var tracing: TracingConfiguration { .default }
}