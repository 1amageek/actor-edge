import Foundation
import Metrics

/// Configuration for metrics collection
public struct MetricsConfiguration: Sendable {
    public let enabled: Bool
    public let namespace: String
    public let labels: [String: String]
    public let factory: MetricsFactory?
    
    public init(
        enabled: Bool = true,
        namespace: String = "actoredge",
        labels: [String: String] = [:],
        factory: MetricsFactory? = nil
    ) {
        self.enabled = enabled
        self.namespace = namespace
        self.labels = labels
        self.factory = factory
    }
    
    public static let `default` = MetricsConfiguration()
    
    public static let disabled = MetricsConfiguration(enabled: false)
    
    /// Bootstrap the metrics system with the provided factory
    public func bootstrap() {
        guard enabled, let factory = factory else { return }
        MetricsSystem.bootstrap(factory)
    }
}

/// Pre-defined metric labels for ActorEdge
public struct MetricLabels {
    public static let callID = "call_id"
    public static let actorID = "actor_id"
    public static let method = "method"
    public static let status = "status"
    public static let errorType = "error_type"
}

/// Metric names used throughout ActorEdge
public struct MetricNames: Sendable {
    private let namespace: String
    
    public init(namespace: String = "actor_edge") {
        self.namespace = namespace
    }
    
    // CallLifecycleManager metrics
    public var inflightCalls: String { "\(namespace)_inflight_calls" }
    public var callsTimedOutTotal: String { "\(namespace)_calls_timed_out_total" }
    public var callLatencySeconds: String { "\(namespace)_call_latency_seconds" }
    public var drainDurationSeconds: String { "\(namespace)_drain_duration_seconds" }
    
    // GRPCActorTransport metrics
    public var grpcRequestsTotal: String { "\(namespace)_grpc_requests_total" }
    public var grpcErrorsTotal: String { "\(namespace)_grpc_errors_total" }
    
    // ActorEdgeSystem metrics
    public var distributedCallsTotal: String { "\(namespace)_distributed_calls_total" }
    public var methodInvocationsTotal: String { "\(namespace)_method_invocations_total" }
}