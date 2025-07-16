import Foundation

/// Configuration for distributed tracing
public struct TracingConfiguration: Sendable {
    public let enabled: Bool
    public let serviceName: String
    public let sampleRate: Double
    
    public init(
        enabled: Bool = true,
        serviceName: String = "actoredge-server",
        sampleRate: Double = 1.0
    ) {
        self.enabled = enabled
        self.serviceName = serviceName
        self.sampleRate = sampleRate
    }
    
    public static let `default` = TracingConfiguration()
    
    public static let disabled = TracingConfiguration(enabled: false)
}