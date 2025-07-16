import Foundation

/// Protocol that combines Codable requirements for ActorEdge serialization
public protocol ActorEdgeSerializable: Codable, Sendable {}

/// Extension to make common types conform to ActorEdgeSerializable
extension String: ActorEdgeSerializable {}
extension Int: ActorEdgeSerializable {}
extension Int8: ActorEdgeSerializable {}
extension Int16: ActorEdgeSerializable {}
extension Int32: ActorEdgeSerializable {}
extension Int64: ActorEdgeSerializable {}
extension UInt: ActorEdgeSerializable {}
extension UInt8: ActorEdgeSerializable {}
extension UInt16: ActorEdgeSerializable {}
extension UInt32: ActorEdgeSerializable {}
extension UInt64: ActorEdgeSerializable {}
extension Double: ActorEdgeSerializable {}
extension Float: ActorEdgeSerializable {}
extension Bool: ActorEdgeSerializable {}
extension Data: ActorEdgeSerializable {}
extension Date: ActorEdgeSerializable {}
extension URL: ActorEdgeSerializable {}
extension UUID: ActorEdgeSerializable {}

/// Extension for optional types
extension Optional: ActorEdgeSerializable where Wrapped: ActorEdgeSerializable {}

/// Extension for array types
extension Array: ActorEdgeSerializable where Element: ActorEdgeSerializable {}

/// Extension for dictionary types
extension Dictionary: ActorEdgeSerializable where Key: ActorEdgeSerializable, Value: ActorEdgeSerializable {}