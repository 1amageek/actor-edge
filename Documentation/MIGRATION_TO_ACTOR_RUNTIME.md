# ActorEdge Migration to ActorRuntime

## Overview

This document outlines the migration plan for ActorEdge to use [swift-actor-runtime](https://github.com/1amageek/swift-actor-runtime) as its foundation. This migration will significantly simplify ActorEdge by leveraging shared, battle-tested primitives.

## Motivation

### Current State (Problems)

ActorEdge currently implements its own versions of:
- `ActorRegistry` - Actor instance management
- `ActorEdgeInvocationEncoder` - Method call encoding
- `ActorEdgeInvocationDecoder` - Method call decoding
- `ActorEdgeResultHandler` - Result handling
- `Envelope` / `ActorEdgeEnvelope` - Message containers
- `InvocationData` / `InvocationState` - Invocation management

**Problems:**
1. **Code Duplication**: Same logic exists in multiple projects (Bleu, ActorEdge)
2. **Maintenance Burden**: Bug fixes must be replicated across projects
3. **Testing Overhead**: Each implementation requires separate test suites
4. **Inconsistency Risk**: Implementations may diverge over time

### Target State (Benefits)

With ActorRuntime integration:
- **Shared Foundation**: Common runtime primitives across all distributed actor implementations
- **Simplified Codebase**: ~500-800 lines of code removed from ActorEdge
- **Better Testing**: Leverage ActorRuntime's comprehensive test suite
- **Focus on Transport**: ActorEdge focuses solely on gRPC transport implementation

## Architecture Comparison

### Before (Current Architecture)

```
ActorEdge
├── ActorEdgeSystem (DistributedActorSystem)
├── ActorRegistry (custom implementation)
├── ActorEdgeInvocationEncoder (custom implementation)
├── ActorEdgeInvocationDecoder (custom implementation)
├── ActorEdgeResultHandler (custom implementation)
├── Envelope / ActorEdgeEnvelope (custom message format)
├── InvocationData / InvocationState (custom state management)
├── GRPCMessageTransport (gRPC-specific)
└── Server Protocol (declarative server setup)
```

### After (Target Architecture)

```
ActorEdge
├── ActorEdgeSystem (DistributedActorSystem)
│   ├── Uses: ActorRuntime.ActorRegistry
│   ├── Uses: ActorRuntime.CodableInvocationEncoder
│   ├── Uses: ActorRuntime.CodableInvocationDecoder
│   └── Uses: ActorRuntime.CodableResultHandler
├── GRPCTransport (implements ActorRuntime.DistributedTransport)
│   ├── Converts: InvocationEnvelope ↔ gRPC Messages
│   └── Converts: ResponseEnvelope ↔ gRPC Responses
└── Server Protocol (declarative server setup)
    └── Uses: GRPCTransport
```

## Component Mapping

### 1. Envelope System

**Current:**
```swift
// ActorEdge custom envelope
struct Envelope {
    let recipient: ActorEdgeID
    let sender: ActorEdgeID?
    let manifest: SerializationManifest
    let payload: Data
    let metadata: MessageMetadata
    let messageType: MessageType
}
```

**Target:**
```swift
// Use ActorRuntime envelopes
import ActorRuntime

// InvocationEnvelope from ActorRuntime
struct InvocationEnvelope {
    let callID: String
    let recipientID: String
    let senderID: String?
    let target: String
    let genericSubstitutions: [String]
    let arguments: [Data]
    let metadata: Metadata
}

// ResponseEnvelope from ActorRuntime
struct ResponseEnvelope {
    let callID: String
    let result: InvocationResult
    let metadata: Metadata
}
```

### 2. Actor Registry

**Current:**
```swift
// Sources/ActorEdgeCore/ActorRegistry.swift
public final class ActorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var actors: [ActorEdgeID: any DistributedActor] = [:]
    // ... custom implementation
}
```

**Target:**
```swift
// Use ActorRuntime.ActorRegistry
import ActorRuntime

// ActorEdgeSystem wraps ActorRuntime's registry
public final class ActorEdgeSystem {
    private let registry: ActorRuntime.ActorRegistry
}
```

**Migration:** Convert `ActorEdgeID` to `String` when interfacing with ActorRuntime registry.

### 3. Invocation Encoder/Decoder

**Current:**
```swift
// Sources/ActorEdgeCore/Invocation/ActorEdgeInvocationEncoder.swift
public struct ActorEdgeInvocationEncoder: DistributedTargetInvocationEncoder {
    // ~150 lines of custom implementation
}

// Sources/ActorEdgeCore/Invocation/ActorEdgeInvocationDecoder.swift
public struct ActorEdgeInvocationDecoder: DistributedTargetInvocationDecoder {
    // ~120 lines of custom implementation
}
```

**Target:**
```swift
// Use ActorRuntime codecs
import ActorRuntime

public final class ActorEdgeSystem: DistributedActorSystem {
    public typealias InvocationEncoder = CodableInvocationEncoder
    public typealias InvocationDecoder = CodableInvocationDecoder
    public typealias ResultHandler = CodableResultHandler
}
```

### 4. Result Handler

**Current:**
```swift
// Sources/ActorEdgeCore/Invocation/ActorEdgeResultHandler.swift
public final class ActorEdgeResultHandler: DistributedTargetInvocationResultHandler {
    // ~100 lines of custom implementation
}
```

**Target:**
```swift
// Use ActorRuntime.CodableResultHandler
import ActorRuntime

// Automatically used via ActorEdgeSystem typealias
```

### 5. Transport Layer

**Current:**
```swift
// Sources/ActorEdgeCore/Transport/MessageTransport.swift (custom protocol)
public protocol MessageTransport: Sendable {
    func send(_ envelope: Envelope) async throws -> Envelope?
}

// Sources/ActorEdgeCore/Transports/GRPCMessageTransport.swift
public final class GRPCMessageTransport: MessageTransport {
    // gRPC-specific implementation
}
```

**Target:**
```swift
// Conform to ActorRuntime.DistributedTransport
import ActorRuntime

public final class GRPCTransport: DistributedTransport {
    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope
    var incomingInvocations: AsyncStream<InvocationEnvelope> { get }
    func sendResponse(_ envelope: ResponseEnvelope) async throws
    func close() async throws
}
```

## Migration Plan

### Phase 1: Foundation Setup ✅

- [x] Add ActorRuntime 0.2.0 dependency to Package.swift
- [x] Review current implementation and document migration strategy

### Phase 2: New Implementation

#### 2.1 GRPCTransport Implementation

Create `Sources/ActorEdgeCore/Transport/GRPCTransport.swift`:

```swift
import ActorRuntime
import GRPCCore

public final class GRPCTransport: DistributedTransport {
    private let client: GRPCClient
    private let pendingResponses: PendingResponseStorage

    // Convert ActorRuntime envelopes to/from gRPC protobuf messages
    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope
    public var incomingInvocations: AsyncStream<InvocationEnvelope>
    public func sendResponse(_ envelope: ResponseEnvelope) async throws
    public func close() async throws
}

// Extension for protobuf conversion
extension InvocationEnvelope {
    func toProto() -> ActorEdgeProto_InvocationEnvelope
    init(proto: ActorEdgeProto_InvocationEnvelope) throws
}

extension ResponseEnvelope {
    func toProto() -> ActorEdgeProto_ResponseEnvelope
    init(proto: ActorEdgeProto_ResponseEnvelope) throws
}
```

**Key Design Decision:** GRPCTransport's sole responsibility is converting between ActorRuntime's envelope format and gRPC protobuf messages.

#### 2.2 ActorEdgeSystem Refactoring

Update `Sources/ActorEdgeCore/ActorEdgeSystem.swift`:

```swift
import ActorRuntime

public final class ActorEdgeSystem: DistributedActorSystem {
    // Use ActorRuntime types
    public typealias InvocationEncoder = CodableInvocationEncoder
    public typealias InvocationDecoder = CodableInvocationDecoder
    public typealias ResultHandler = CodableResultHandler

    // Wrap ActorRuntime registry
    private let registry: ActorRuntime.ActorRegistry

    // ActorEdge-specific: Transport and configuration
    private let transport: DistributedTransport?
    private let configuration: Configuration

    // Client-side remoteCall implementation
    public func remoteCall<Act, Err, Res>(...) async throws -> Res {
        // 1. Create encoder via makeInvocationEncoder()
        // 2. Encode invocation to InvocationEnvelope
        // 3. Send via transport.sendInvocation()
        // 4. Decode ResponseEnvelope result
    }

    // Server-side actor management
    public func actorReady<Act>(_ actor: Act) {
        registry.register(actor, id: String(describing: actor.id))
    }
}
```

#### 2.3 Protobuf Schema Update

Update `distributed_actor.proto` to match ActorRuntime envelope structure:

```protobuf
syntax = "proto3";
package ActorEdgeProto;

// Matches ActorRuntime.InvocationEnvelope
message InvocationEnvelope {
  string call_id = 1;
  string recipient_id = 2;
  string sender_id = 3;
  string target = 4;
  repeated string generic_substitutions = 5;
  repeated bytes arguments = 6;

  message Metadata {
    google.protobuf.Timestamp timestamp = 1;
    map<string, string> headers = 2;
  }
  Metadata metadata = 7;
}

// Matches ActorRuntime.ResponseEnvelope
message ResponseEnvelope {
  string call_id = 1;

  oneof result {
    bytes success = 2;
    Void void = 3;
    Error failure = 4;
  }

  message Metadata {
    google.protobuf.Timestamp timestamp = 1;
    double execution_time = 2;
    map<string, string> headers = 3;
  }
  Metadata metadata = 5;

  message Void {}
  message Error {
    string kind = 1;
    string message = 2;
  }
}

service DistributedActor {
  rpc RemoteCall(InvocationEnvelope) returns (ResponseEnvelope);
  rpc StreamCall(stream InvocationEnvelope) returns (stream ResponseEnvelope);
}
```

### Phase 3: File Removal

Delete obsolete implementations:

```bash
# Remove duplicate implementations
rm Sources/ActorEdgeCore/ActorRegistry.swift
rm Sources/ActorEdgeCore/Invocation/ActorEdgeInvocationEncoder.swift
rm Sources/ActorEdgeCore/Invocation/ActorEdgeInvocationDecoder.swift
rm Sources/ActorEdgeCore/Invocation/ActorEdgeResultHandler.swift
rm Sources/ActorEdgeCore/Invocation/InvocationData.swift
rm Sources/ActorEdgeCore/Invocation/InvocationState.swift
rm Sources/ActorEdgeCore/Invocation/DistributedInvocationProcessor.swift

# Remove old envelope system
rm Sources/ActorEdgeCore/Transport/ActorEdgeEnvelope.swift
rm Sources/ActorEdgeCore/Serialization/SerializationManifest.swift
rm Sources/ActorEdgeCore/Serialization/SerializationContext.swift
rm Sources/ActorEdgeCore/Serialization/SerializationSystem.swift

# Remove old transport implementations
rm Sources/ActorEdgeCore/Transport/MessageTransport.swift
rm Sources/ActorEdgeCore/Transports/GRPCMessageTransport.swift
rm Sources/ActorEdgeCore/Transports/GRPCServerTransport.swift
rm Sources/ActorEdgeCore/Transports/InMemoryMessageTransport.swift
```

**Files to Keep:**
- `ActorEdgeSystem.swift` (refactored)
- `ActorEdgeID.swift` (ActorEdge-specific ID type)
- `Server.swift` (declarative server protocol)
- `TLSConfiguration.swift` (TLS support)
- Configuration files (MetricsConfiguration, TracingConfiguration, etc.)

### Phase 4: Server Integration

Update `Sources/ActorEdgeServer/ServerExtension.swift`:

```swift
import ActorRuntime

extension Server {
    public static func main() async throws {
        let config = ServerConfiguration()
        let registry = ActorRuntime.ActorRegistry()
        let system = ActorEdgeSystem(registry: registry, configuration: config)

        // Create actors using @ActorBuilder
        let actorInstances = self.init().actors(actorSystem: system)

        // Start gRPC server with GRPCTransport
        let transport = try await GRPCTransport.server(
            host: config.host,
            port: config.port,
            registry: registry
        )

        // ServiceLifecycle integration
        try await withGracefulShutdown {
            try await transport.run()
        }
    }
}
```

### Phase 5: Testing

Update tests to use ActorRuntime components:

```swift
import Testing
import ActorRuntime
@testable import ActorEdge

@Test func testActorRegistration() async throws {
    let system = ActorEdgeSystem(configuration: .default)
    let actor = TestActor(actorSystem: system)

    // Verify ActorRuntime registry integration
    let found = system.registry.find(id: String(describing: actor.id))
    #expect(found != nil)
}
```

## Benefits After Migration

### Code Reduction
- **Removed:** ~800 lines of duplicate implementation
- **Added:** ~200 lines of GRPCTransport adapter
- **Net Reduction:** ~600 lines

### Simplified Maintenance
- Bug fixes in encoding/decoding happen once in ActorRuntime
- Shared test coverage across Bleu, ActorEdge, and future projects
- Single source of truth for distributed actor primitives

### Clearer Responsibility
- **ActorRuntime:** Envelope format, encoding, decoding, registry, error handling
- **ActorEdge:** gRPC transport, TLS configuration, server lifecycle, declarative API

## Migration Checklist

- [x] Add ActorRuntime dependency
- [ ] Create new protobuf schema matching ActorRuntime envelopes
- [ ] Implement GRPCTransport conforming to DistributedTransport
- [ ] Refactor ActorEdgeSystem to use ActorRuntime components
- [ ] Update Server protocol integration
- [ ] Remove obsolete implementations
- [ ] Update tests
- [ ] Update CLAUDE.md documentation
- [ ] Update examples (Chat)
- [ ] Performance benchmarking (ensure no regression)

## Compatibility

### Breaking Changes
This is a **breaking change** for ActorEdge users:

1. **Internal API Changes:** Users relying on internal types like `ActorEdgeEnvelope` will need updates
2. **Custom Transport Implementations:** Must migrate to `DistributedTransport` protocol

### Non-Breaking for End Users
The public API remains unchanged:
- `@Resolvable` protocol usage
- `Server` protocol and `@ActorBuilder`
- Client connection APIs
- TLS configuration

## Timeline

1. **Phase 1:** ✅ Complete (Foundation setup)
2. **Phase 2:** Design and implement GRPCTransport (1 day)
3. **Phase 3:** Refactor ActorEdgeSystem (1 day)
4. **Phase 4:** Remove obsolete code (0.5 day)
5. **Phase 5:** Testing and validation (1 day)

**Total Estimated Time:** 3.5 days

## References

- [swift-actor-runtime Repository](https://github.com/1amageek/swift-actor-runtime)
- [ActorRuntime DESIGN.md](https://github.com/1amageek/swift-actor-runtime/blob/main/Documentation/DESIGN.md)
- [Swift Distributed Actors Documentation](https://developer.apple.com/documentation/distributed)
