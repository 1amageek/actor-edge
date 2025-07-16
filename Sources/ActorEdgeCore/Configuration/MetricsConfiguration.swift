import Foundation

/// Configuration for metrics collection
public struct MetricsConfiguration: Sendable {
    public let enabled: Bool
    public let namespace: String
    public let labels: [String: String]
    
    public init(
        enabled: Bool = true,
        namespace: String = "actoredge",
        labels: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.namespace = namespace
        self.labels = labels
    }
    
    public static let `default` = MetricsConfiguration()
    
    public static let disabled = MetricsConfiguration(enabled: false)
}