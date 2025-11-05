import Foundation
import Testing
import Distributed
@testable import ActorEdgeCore

/// Test server configuration and helpers
/// For integration tests that need actual gRPC server-client communication

/// Helper to run tests with concurrent server and client
/// Since ActorEdge currently doesn't expose a programmatic server API,
/// we use in-process actor systems for testing
public func withTestActors<T>(
    _ actors: [any DistributedActor],
    _ body: (ActorEdgeSystem) async throws -> T
) async throws -> T {
    // All actors share the same system for in-process testing
    guard let firstActor = actors.first else {
        throw TestServerError.noActorsProvided
    }

    // Get the actor system (all actors should use the same system)
    guard let system = firstActor.actorSystem as? ActorEdgeSystem else {
        throw TestServerError.invalidActorSystem
    }

    return try await body(system)
}

/// Simplified test server helper that works with current ActorEdge implementation
/// For remote call tests, we rely on the in-process path which exercises
/// the same encoder/decoder logic without actual network
public func withTestServer<T>(
    actors: [any DistributedActor],
    configuration: TestServerConfiguration = .default,
    _ body: (Int) async throws -> T
) async throws -> T {
    // For now, we use in-process testing
    // Remote gRPC tests require actual server startup which is
    // handled by ActorEdgeService (not directly accessible for testing)

    return try await withTestActors(actors) { system in
        // Return a mock port - tests will use local resolution
        try await body(configuration.port)
    }
}

/// Test server configuration
public struct TestServerConfiguration: Sendable {
    let host: String
    let port: Int
    let logLevel: String

    public init(
        host: String = "127.0.0.1",
        port: Int = 50051,
        logLevel: String = "critical"
    ) {
        self.host = host
        self.port = port
        self.logLevel = logLevel
    }

    public static let `default` = TestServerConfiguration()
}
