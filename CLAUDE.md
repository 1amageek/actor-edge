# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build
swift build

### Test
swift test

### Run specific test
swift test --filter TestName

### Generate Protobuf files
SwiftProtobufPlugin automatically generates Swift code during build
Configuration: Sources/ActorEdgeCore/swift-protobuf-config.json

### Clean build
swift package clean

## Architecture Overview

ActorEdge is a lightweight gRPC-based distributed actor RPC framework that enables declarative server definitions using Swift's distributed actors. It leverages SE-0428's `@Resolvable` macro to provide type-safe client stubs without requiring clients to know server implementations.

Built on gRPC Swift 2.0, ActorEdge fully embraces Swift's modern async/await concurrency model, providing a natural and idiomatic API for distributed actor communication. The framework integrates seamlessly with Swift's structured concurrency while maintaining the distributed actor programming model.

**Important**: This implementation requires macOS 15.0+ due to gRPC Swift 2.0 and Distributed Actor dependencies.

### Core Design Pattern

ActorEdge uses a three-module architecture:

1. **SharedAPI Module**: Contains `@Resolvable` protocol definitions
2. **Server Module**: Implements protocols with concrete distributed actors
3. **Client Module**: Uses auto-generated `$ProtocolName` stubs

Example:
```swift
// SharedAPI module
@Resolvable
public protocol Chat: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func send(_ text: String) async throws
    distributed func subscribe() async throws -> AsyncStream<Message>
}

// Server module
@main
public struct ChatServer: Server {
    public init() {}
    
    @ActorBuilder
    public func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatServerActor(actorSystem: actorSystem)
    }
    
    // Use default port 8000 and host 127.0.0.1
    // Override only if needed:
    // public var port: Int { 9000 }
    // public var host: String { "0.0.0.0" }  // For external access
}

// Distributed actor implementation
public distributed actor ChatServerActor: Chat {
    public typealias ActorSystem = ActorEdgeSystem
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func send(_ text: String) async throws {
        logger.info("Received: \(text)")
    }
    
    public distributed func subscribe() async throws -> AsyncStream<Message> {
        // Return message stream
    }
}

// Client module - uses auto-generated $Chat stub
let transport = try await GRPCActorTransport("127.0.0.1:8000")
let system = ActorEdgeSystem(transport: transport)
let chat = try $Chat.resolve(id: ActorEdgeID(), using: system)
try await chat.send("Hello")
```

### Server Configuration

The `Server` protocol provides declarative configuration through computed properties and the `@ActorBuilder` pattern:

```swift
public protocol Server {
    init()
    
    // Actor Configuration
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor]
    
    // Network Configuration
    var port: Int { get }
    var host: String { get }
    var tls: TLSConfiguration? { get }
    var middleware: [any ServerMiddleware] { get }
    var maxConnections: Int { get }
    var timeout: TimeInterval { get }
    var metrics: MetricsConfiguration { get }
    var tracing: TracingConfiguration { get }
}

// Default implementations provided
extension Server {
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] { [] }
    
    var port: Int { 8000 }              // Default port like Deno
    var host: String { "127.0.0.1" }    // Secure default: localhost only
    var tls: TLSConfiguration? { nil }
    var middleware: [any ServerMiddleware] { [] }
    var maxConnections: Int { 1000 }
    var timeout: TimeInterval { 30 }
    var metrics: MetricsConfiguration { .default }
    var tracing: TracingConfiguration { .default }
}
```

The `main()` function is provided by a Server extension that reads these configuration properties and sets up the gRPC server with ServiceLifecycle.

### Core Components

**ActorEdgeSystem**
- `DistributedActorSystem` implementation for non-cluster environments
- Manages actor lifecycle and remote call dispatch
- Integrates with `ActorTransport` for network communication
- Server-side actor registry for method dispatch

**GRPCActorTransport** 
- Client-side `ActorTransport` implementation using gRPC Swift 2.0
- Uses modern `GRPCClient` with async/await APIs
- Manages single HTTP/2 connection per endpoint
- Handles protobuf message serialization

**Server Protocol Extension**
- Provides `static func main()` implementation
- Creates `GRPCServer` with async/await support
- Uses `ServiceLifecycle.ServiceGroup` for lifecycle management
- Configures server from declarative protocol properties

**DistributedActorService**
- Custom `RegistrableRPCService` implementation
- Registers RPC handlers without protobuf code generation
- Handles method dispatch to distributed actors
- Supports both unary and streaming RPCs

**InvocationEncoder/Decoder**
- Binary serialization format for method arguments
- Supports generic type substitutions
- Compatible with swift-distributed-actors wire format
- Wrapped in protobuf messages for transport

### Package Structure

```
Sources/
├── ActorEdge/              # Public API
│   └── ActorEdge.swift     # @_exported imports
├── ActorEdgeCore/          # Core functionality
│   ├── ActorEdgeID.swift
│   ├── ActorEdgeSystem.swift
│   ├── ActorRegistry.swift
│   ├── GRPCActorTransport.swift
│   ├── Protocols/
│   │   ├── ActorTransport.swift
│   │   ├── Server.swift    # Server protocol with config
│   │   └── ServerMiddleware.swift
│   ├── Configuration/
│   │   ├── MetricsConfiguration.swift
│   │   ├── TLSConfiguration.swift
│   │   └── TracingConfiguration.swift
│   ├── Errors/
│   │   └── ActorEdgeError.swift
│   ├── Invocation/
│   │   ├── ActorEdgeInvocationDecoder.swift
│   │   ├── ActorEdgeInvocationEncoder.swift
│   │   └── ActorEdgeResultHandler.swift
│   ├── Builders/           # Empty directory for future builder components
│   ├── Tracing/            # Empty directory for future tracing components
│   ├── distributed_actor.proto    # Protobuf service definition
│   └── swift-protobuf-config.json # SwiftProtobufPlugin configuration
├── ActorEdgeServer/        # Server-specific
│   ├── DistributedActorService.swift
│   └── ServerExtension.swift    # main() implementation
└── ActorEdgeClient/        # Client-specific
    └── Connect.swift
```

### gRPC Swift 2.0 Integration

ActorEdge leverages gRPC Swift 2.0's modern architecture:

**Client Implementation**
```swift
public final class GRPCActorTransport: ActorTransport {
    private let client: GRPCClient
    
    public init(_ endpoint: String, tls: ClientTLSConfiguration? = nil) async throws {
        self.client = GRPCClient(
            transport: try .http2NIOPosix(
                target: .host(endpoint),
                transportSecurity: tls != nil ? .tls : .plaintext
            )
        )
    }
    
    public func remoteCall(...) async throws -> Data {
        let response = try await client.unary(
            request: ClientRequest(message: protoRequest),
            descriptor: MethodDescriptor(
                service: "actoredge.DistributedActor",
                method: "RemoteCall"
            ),
            serializer: ProtobufSerializer<Actoredge_RemoteCallRequest>(),
            deserializer: ProtobufDeserializer<Actoredge_RemoteCallResponse>()
        )
        // Handle response
    }
}
```

**Server Implementation**
```swift
final class DistributedActorService: RegistrableRPCService {
    func registerMethods(with router: inout RPCRouter) {
        router.registerHandler(
            forMethod: MethodDescriptor(
                service: "actoredge.DistributedActor",
                method: "RemoteCall"
            ),
            deserializer: ProtobufDeserializer<Actoredge_RemoteCallRequest>(),
            serializer: ProtobufSerializer<Actoredge_RemoteCallResponse>()
        ) { (request: ServerRequest<Actoredge_RemoteCallRequest>, context: ServerContext) in
            // Decode invocation and dispatch to actor
            let result = try await self.system.executeDistributedTarget(...)
            return ServerResponse(message: .with { $0.value = result })
        }
    }
}
```

### Wire Protocol

gRPC service definition:
```proto
service DistributedActor {
  rpc RemoteCall(RemoteCallRequest) returns (RemoteCallResponse);
  rpc StreamCall(stream RemoteStreamPacket) returns (stream RemoteStreamPacket);
}

message RemoteCallRequest {
  string actor_id = 1;   // 96-bit UUID, base64url
  string method   = 2;   // mangled func signature
  bytes  payload  = 3;   // arguments via InvocationEncoder
}
```

### Implementation Status

✅ **Completed**:
1. **Package.swift**: Added all dependencies including gRPC Swift 2.0
2. **Core Types**: Implemented `ActorEdgeSystem`, `ActorTransport` protocol
3. **Serialization**: Created `ActorEdgeInvocationEncoder/Decoder` with JSON format
4. **Server Protocol**: Implemented `Server` protocol with `@ActorBuilder` and `main()` extension
5. **Transport**: `GRPCActorTransport` implementation with async/await
6. **Service**: `DistributedActorService` as RegistrableRPCService
7. **Protobuf**: SwiftProtobufPlugin for automatic code generation
8. **Error Handling**: Basic `ErrorEnvelope` implementation
9. **Actor Registry**: Server-side actor registration and lookup system
10. **Method Invocation**: Runtime distributed method execution with ResultHandler
11. **ActorBuilder**: SwiftUI-style declarative actor configuration
12. **Examples**: Complete Chat example with SharedAPI, Server, and Client
13. **Testing Strategy**: Comprehensive testing framework and guidelines

⏳ **Pending**:
1. **Binary Serialization**: Switch from JSON to binary format for performance
2. **ServiceLifecycle**: Enhanced integration with ServiceGroup
3. **Test Implementation**: Unit, integration, and performance tests
4. **TLS Support**: Production-ready TLS configuration
5. **Middleware System**: Request/response middleware pipeline

### Key Implementation Notes

- **gRPC Swift 2.0**: Uses modern async/await APIs throughout, no EventLoopFutures
- **Custom Service**: Implements `RegistrableRPCService` without protobuf service generation
- **Message Format**: ActorEdge invocation format wrapped in protobuf for transport
- **@Resolvable Usage**: Protocols must inherit from `DistributedActor`, contain only `distributed func` methods, no associated types, and all parameter/return types must be `Codable & Sendable`
- **Single Connection**: Each `GRPCClient` maintains one HTTP/2 connection per endpoint
- **Error Propagation**: Remote errors are wrapped in `ErrorEnvelope` and re-thrown on client
- **Context Propagation**: Trace/Baggage context propagated via gRPC metadata
- **Binary Size**: Keep iOS delta < 1.4MB by careful dependency management
- **ServiceLifecycle**: Server uses `ServiceGroup` for proper lifecycle management
- **ActorBuilder**: SwiftUI-style `@ActorBuilder` for declarative actor configuration
- **SwiftProtobufPlugin**: Automatic protobuf code generation during build

### Design Constraints

- No clustering or service discovery (unlike swift-distributed-actors)
- TLS 1.3 mandatory for production use
- Client and server must share identical API module version
- All distributed methods must be async throws

## Testing Strategy

### Test Development Approach

1. **Incremental Testing**: Implement tests one at a time, completing each test fully before moving to the next
2. **Test-First Analysis**: When tests fail, analyze whether the issue is in the test implementation or the actual code
3. **Structural Analysis**: Consider the overall architecture and design patterns when debugging test failures
4. **Swift Testing Framework**: Use Swift Testing with async/await support for modern testing patterns

### Test Structure

```
Tests/
├── ActorEdgeTests/
│   ├── Unit/
│   │   ├── ActorEdgeSystemTests.swift
│   │   ├── ActorBuilderTests.swift
│   │   ├── SerializationTests.swift
│   │   └── TransportTests.swift
│   ├── Integration/
│   │   ├── ServerClientTests.swift
│   │   ├── DistributedActorTests.swift
│   │   └── EndToEndTests.swift
│   ├── Performance/
│   │   ├── ThroughputTests.swift
│   │   └── LatencyTests.swift
│   └── Mocks/
│       ├── MockActorTransport.swift
│       └── MockGRPCClient.swift
└── SampleTests/
    └── ChatTests.swift
```

### Test Categories

1. **Unit Tests**: Core component functionality in isolation
2. **Integration Tests**: Component interaction and communication
3. **Performance Tests**: Throughput, latency, and memory usage
4. **End-to-End Tests**: Complete workflow validation

### Testing Principles

- Use `@Test` and `@Suite` from Swift Testing framework
- Leverage `async/await` for distributed actor testing
- Use `confirmation()` API for asynchronous event testing
- Apply `@Suite(.serialized)` for shared state tests
- Implement dependency injection for mocking
- Maintain test isolation with independent actor systems

### Commit Message Guidelines

- Write clear, concise commit messages describing changes
- Focus on technical implementation details
- Do not include promotional content or advertising
- Keep messages professional and informative