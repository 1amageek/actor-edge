import Foundation
import Distributed
@testable import ActorEdgeCore
@testable import ActorEdgeServer

/// Simple test server for basic actor testing
public struct SimpleTestServer: Server {
    private let testPort: Int
    private let testTLS: TLSConfiguration?
    private let actorFactories: [@Sendable (ActorEdgeSystem) -> any DistributedActor]
    private let testActorIDs: [ActorEdgeID]
    private let testMetrics: MetricsConfiguration

    // Required by Server protocol
    public init() {
        self.testPort = 50001
        self.testTLS = nil
        self.actorFactories = []
        self.testActorIDs = []
        self.testMetrics = .default
    }

    public init(
        port: Int = 50001,
        tls: TLSConfiguration? = nil,
        actors: [@Sendable (ActorEdgeSystem) -> any DistributedActor],
        actorIDs: [ActorEdgeID] = [],
        metrics: MetricsConfiguration = .default
    ) {
        self.testPort = port
        self.testTLS = tls
        self.actorFactories = actors
        self.testActorIDs = actorIDs
        self.testMetrics = metrics
    }

    public var port: Int { testPort }
    public var host: String { "127.0.0.1" }
    public var tls: TLSConfiguration? { testTLS }
    public var actorIDs: [ActorEdgeID] { testActorIDs }
    public var metrics: MetricsConfiguration { testMetrics }

    @ActorBuilder
    public func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        actorFactories.map { $0(actorSystem) }
    }
}
