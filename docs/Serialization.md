# ActorEdge Serialization System Specification

## Overview

This document describes the serialization system for ActorEdge, which is designed to fully follow the patterns established by [swift-distributed-actors](https://github.com/apple/swift-distributed-actors). The serialization system is responsible for encoding and decoding distributed actor method invocations, arguments, and return values for transmission over the network.

## Design Principles

1. **Complete Compatibility**: Follow swift-distributed-actors patterns exactly
2. **Type Safety**: Maintain type information through the serialization process
3. **Extensibility**: Support future serialization formats beyond JSON
4. **Performance**: Minimize allocations and copies where possible

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                   ActorEdgeSystem                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────┐      ┌──────────────────────┐    │
│  │ InvocationEncoder│      │ InvocationDecoder    │    │
│  └────────┬─────────┘      └──────────┬──────────┘    │
│           │                            │                │
│           ▼                            ▼                │
│  ┌─────────────────────────────────────────────────┐   │
│  │            ActorEdgeSerialization               │   │
│  ├─────────────────────────────────────────────────┤   │
│  │ • serialize<T>() -> SerializationBuffer         │   │
│  │ • deserialize<T>() -> T                         │   │
│  │ • outboundManifest() -> SerializationManifest   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Outbound (Encoding)**:
   ```
   Method Call → InvocationEncoder → Serialization → Buffer → Network
   ```

2. **Inbound (Decoding)**:
   ```
   Network → Buffer → Serialization → InvocationDecoder → Method Execution
   ```

## Component Specifications

### SerializationBuffer

Represents serialized data in memory. Initially supports only `Data` format, with potential for future `ByteBuffer` support.

```swift
public enum SerializationBuffer {
    case data(Data)
    
    /// Get the number of bytes in the buffer
    public var count: Int { get }
    
    /// Read the buffer as Data (may involve copying)
    public func readData() -> Data
}
```

### SerializationManifest

Carries type information necessary for deserialization. Replaces swift-distributed-actors' hint-based system with explicit type names.

```swift
public struct SerializationManifest: Codable, Sendable {
    /// Identifies which serializer to use
    public let serializerID: SerializerID
    
    /// Type name for deserialization (replaces hint)
    public let typeName: String
    
    public init(serializerID: SerializerID, typeName: String)
}
```

### SerializerID

Identifies the serialization format. Initially only JSON is supported.

```swift
public enum SerializerID: UInt32, Codable, Sendable {
    case json = 3  // Matches swift-distributed-actors' foundationJSON
    
    // Future additions:
    // case protobuf = 2
    // case propertyListBinary = 4
}
```

### ActorEdgeSerialization

The main serialization engine that manages encoding and decoding of values.

```swift
public final class ActorEdgeSerialization: Sendable {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let system: ActorEdgeSystem
    
    /// Serialize a value into a buffer
    public func serialize<T: Codable>(_ value: T) throws -> SerializationBuffer
    
    /// Deserialize a value from a buffer
    public func deserialize<T: Codable>(
        _ type: T.Type,
        from buffer: SerializationBuffer,
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) throws -> T
    
    /// Create a manifest for a given type
    public func outboundManifest(_ type: Any.Type) -> SerializationManifest
    
    /// Resolve a type from a manifest
    public func summonType(from manifest: SerializationManifest) throws -> Any.Type
}
```

## InvocationEncoder/Decoder Integration

### InvocationEncoder

Following the ClusterInvocationEncoder pattern:

```swift
public struct ActorEdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    private var arguments: [Data] = []
    private var genericSubstitutions: [String] = []
    private let serialization: ActorEdgeSerialization
    
    public mutating func recordArgument<Value>(
        _ argument: RemoteCallArgument<Value>
    ) throws where Value: SerializationRequirement {
        let buffer = try serialization.serialize(argument.value)
        arguments.append(buffer.readData())
    }
    
    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        genericSubstitutions.append(String(reflecting: type))
    }
}
```

### InvocationDecoder

Following the ClusterInvocationDecoder pattern:

```swift
public struct ActorEdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    private enum State {
        case remoteCall(InvocationMessage)
        case localCall(ActorEdgeInvocationEncoder)
    }
    
    private let state: State
    private let serialization: ActorEdgeSerialization
    private var argumentIndex = 0
    
    public mutating func decodeNextArgument<Argument>() throws -> Argument {
        // Critical: Set actorSystem in userInfo for distributed actor deserialization
        let userInfo = [CodingUserInfoKey.actorSystemKey: system]
        
        let data = getCurrentArgumentData()
        let buffer = SerializationBuffer.data(data)
        
        return try serialization.deserialize(
            Argument.self,
            from: buffer,
            userInfo: userInfo
        )
    }
}
```

### Distributed Actor Arguments

When a distributed actor is passed as an argument:

1. **Encoding**: The actor's ID is serialized
2. **Decoding**: The ID is deserialized and resolved back to an actor reference using the actor system in userInfo

This requires proper userInfo configuration:

```swift
decoder.userInfo[.actorSystemKey] = actorSystem
```

## Remote Call Flow

### Complete Flow with CheckedContinuation

```swift
public func remoteCall<Act, Err, Res>(...) async throws -> Res {
    return try await withCallID(timeout: timeout) { callID in
        // 1. Create InvocationMessage
        let message = InvocationMessage(
            callID: callID,
            targetIdentifier: target.identifier,
            genericSubstitutions: encoder.genericSubstitutions,
            arguments: encoder.arguments
        )
        
        // 2. Send over transport
        transport.send(message)
        
        // 3. Wait for RemoteCallReply (managed by withCallID)
    }
}

private func withCallID<T>(
    timeout: TimeInterval,
    body: (String) async throws -> Void
) async throws -> T {
    let callID = UUID().uuidString
    
    return try await withCheckedThrowingContinuation { continuation in
        // Store continuation
        inFlightCalls[callID] = continuation
        
        // Setup timeout
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if let continuation = inFlightCalls.removeValue(forKey: callID) {
                continuation.resume(throwing: ActorEdgeError.timeout)
            }
        }
        
        // Execute call
        Task {
            try await body(callID)
        }
    }
}
```

### InvocationMessage Structure

```swift
public struct InvocationMessage: Codable, Sendable {
    public let callID: String
    public let targetIdentifier: String
    public let genericSubstitutions: [String]
    public let arguments: [Data]
    
    /// Convert to RemoteCallTarget
    public var target: RemoteCallTarget {
        RemoteCallTarget(targetIdentifier)
    }
}
```

### RemoteCallReply Structure

```swift
public struct RemoteCallReply: Codable, Sendable {
    public let callID: String
    public let value: Data?
    public let error: RemoteCallError?
    
    public static func success(callID: String, value: Data) -> Self
    public static func failure(callID: String, error: Error) -> Self
}
```

## Implementation Phases

### Phase 1: Core Serialization
- [ ] SerializationBuffer enum
- [ ] SerializationManifest struct
- [ ] SerializerID enum
- [ ] ActorEdgeSerialization class

### Phase 2: Type Resolution
- [ ] TypeResolver improvements
- [ ] Manifest-based type summoning
- [ ] Distributed actor ID handling

### Phase 3: Encoder/Decoder Integration
- [ ] Update InvocationEncoder to use Serialization
- [ ] Update InvocationDecoder with proper userInfo
- [ ] InvocationMessage implementation

### Phase 4: Async Flow
- [ ] CheckedContinuation management
- [ ] Timeout mechanism
- [ ] RemoteCallReply handling

### Phase 5: Testing & Optimization
- [ ] Unit tests for each component
- [ ] Integration tests
- [ ] Performance optimization

## Testing Strategy

1. **Unit Tests**: Test each serialization component in isolation
2. **Integration Tests**: Test the complete flow from encoding to decoding
3. **Distributed Actor Tests**: Verify distributed actors can be passed as arguments
4. **Error Cases**: Test timeout, serialization failures, and type mismatches

## Future Extensions

1. **Additional Serializers**:
   - Protocol Buffers support
   - Binary Property List support
   - Custom binary format

2. **Performance Optimizations**:
   - ByteBuffer support for zero-copy operations
   - Specialized serializers for primitive types
   - Caching of type manifests

3. **Advanced Features**:
   - Compression support
   - Encryption support
   - Versioning and migration

## References

- [swift-distributed-actors Serialization](https://github.com/apple/swift-distributed-actors/tree/main/Sources/DistributedCluster/Serialization)
- [Apple Distributed Actor Documentation](https://developer.apple.com/documentation/distributed)
- [Swift Evolution SE-0336](https://github.com/apple/swift-evolution/blob/main/proposals/0336-distributed-actor-isolation.md)