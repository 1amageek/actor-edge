import Foundation

/// Type resolution system for ActorEdge
/// Optimized for concrete types used in distributed actors
public struct TypeResolver {
    
    /// Resolve a type by its string name
    /// Supports concrete types used in ActorEdge distributed actors
    public static func resolveType(from typeName: String) -> Any.Type? {
        // Concrete type resolution for actual ActorEdge usage
        switch typeName {
        // Swift basic types
        case "Swift.String": return String.self
        case "Swift.Int": return Int.self
        case "Swift.Double": return Double.self
        case "Swift.Bool": return Bool.self
        
        // Foundation types
        case "Foundation.Data": return Data.self
        case "Foundation.Date": return Date.self
        case "Foundation.URL": return URL.self
        case "Foundation.UUID": return UUID.self
        
        // ActorEdge specific types
        case let name where name.contains("InvocationMessage"):
            return InvocationMessage.self
        case let name where name.contains("VoidReturn"):
            return VoidReturn.self
        case let name where name.contains("RemoteCallError"):
            return RemoteCallError.self
        case let name where name.contains("ActorEdgeID"):
            return ActorEdgeID.self
        case let name where name.contains("ActorEdgeError"):
            return ActorEdgeError.self
        case let name where name.contains("ErrorEnvelope"):
            return ErrorEnvelope.self
        
        // Custom type resolution (extensible)
        default:
            return resolveCustomType(typeName)
        }
    }
    
    /// Get the type name for a given type
    /// This is used for serialization/storage of type information
    public static func typeName(for type: Any.Type) -> String {
        return String(reflecting: type)
    }
    
    /// Check if a type name can be resolved
    public static func canResolve(typeName: String) -> Bool {
        return resolveType(from: typeName) != nil
    }
    
    /// Resolve custom application-specific types
    /// Can be extended for specific use cases
    private static func resolveCustomType(_ typeName: String) -> Any.Type? {
        // Check type registry for registered custom types
        if let type = TypeRegistry.shared.type(for: typeName) {
            return type
        }
        
        // Pattern-based resolution for common types
        if typeName.contains("Message") {
            // Log unknown message types for debugging
            print("TypeResolver: Unknown message type '\(typeName)'")
        }
        
        return nil
    }
}

/// Lightweight type registry for custom type resolution
/// Used for application-specific types when needed
public final class TypeRegistry: @unchecked Sendable {
    public static let shared = TypeRegistry()
    
    private var typeMap: [String: Any.Type] = [:]
    private let lock = NSLock()
    
    private init() {
        // Minimal initialization - register only when needed
    }
    
    /// Register a custom type with its string name
    /// Use this for application-specific types
    public func register<T>(_ type: T.Type, as name: String? = nil) {
        let typeName = name ?? String(reflecting: type)
        lock.withLock {
            typeMap[typeName] = type
        }
    }
    
    /// Get a type by its string name
    public func type(for name: String) -> Any.Type? {
        lock.withLock {
            return typeMap[name]
        }
    }
    
    /// Get all registered types (for debugging)
    public func registeredTypes() -> [String] {
        lock.withLock {
            return Array(typeMap.keys)
        }
    }
}

/// Extension for type safety checks and registration
extension TypeResolver {
    
    /// Register a custom type for resolution
    /// Use this for application-specific types
    public static func register<T>(_ type: T.Type, as name: String? = nil) {
        TypeRegistry.shared.register(type, as: name)
    }
    
    /// Check if a type conforms to Codable & Sendable
    public static func isSerializable(_ type: Any.Type) -> Bool {
        return (type is any (Codable & Sendable).Type)
    }
    
    /// Validate that a type can be used in distributed actor calls
    public static func validateDistributedType(_ type: Any.Type) throws {
        guard isSerializable(type) else {
            throw ActorEdgeError.serializationFailed(
                "Type \(String(reflecting: type)) does not conform to Codable & Sendable"
            )
        }
    }
}


/// Extension for NSLock convenience
private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}