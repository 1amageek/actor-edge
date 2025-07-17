import Foundation

/// Marker type for void returns in distributed calls
/// Based on swift-distributed-actors _Done type
public struct VoidReturn: Codable, Sendable, Equatable {
    /// Singleton instance
    public static let instance = VoidReturn()
    
    private init() {}
}

// MARK: - CustomStringConvertible
extension VoidReturn: CustomStringConvertible {
    public var description: String {
        "VoidReturn"
    }
}