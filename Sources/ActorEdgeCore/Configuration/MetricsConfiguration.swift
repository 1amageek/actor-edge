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

/// Metric names used throughout ActorEdge
public struct MetricNames: Sendable {
    private let namespace: String
    
    public init(namespace: String = "actor_edge") {
        self.namespace = namespace
    }
    
    // MessageTransport metrics
    public var messagesEnvelopesSentTotal: String { "\(namespace)_messages_envelopes_sent_total" }
    public var messagesEnvelopesReceivedTotal: String { "\(namespace)_messages_envelopes_received_total" }
    public var messagesEnvelopesErrorsTotal: String { "\(namespace)_messages_envelopes_errors_total" }
    public var messageTransportLatencySeconds: String { "\(namespace)_message_transport_latency_seconds" }
    
    // ActorEdgeSystem metrics
    public var distributedCallsTotal: String { "\(namespace)_distributed_calls_total" }
    public var actorRegistrationsTotal: String { "\(namespace)_actor_registrations_total" }
    public var actorResolutionsTotal: String { "\(namespace)_actor_resolutions_total" }
    
    // Serialization metrics
    public var serializationTotal: String { "\(namespace)_serialization_total" }
    public var deserializationTotal: String { "\(namespace)_deserialization_total" }
    public var serializationErrorsTotal: String { "\(namespace)_serialization_errors_total" }
}