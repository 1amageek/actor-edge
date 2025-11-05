# ActorEdge

Type-safe distributed actors for Swift. Write servers and clients as if they were local actors.

## Overview

ActorEdge brings the simplicity of Swift's distributed actors to client-server development. Using the `@Resolvable` macro, it eliminates boilerplate code and provides compile-time type safety for remote calls. What traditionally requires protocol definitions, code generation, and manual client implementations is reduced to writing a simple Swift protocol.

## Features

- **Zero Boilerplate**: Write a protocol, get both server and client implementations
- **Type Safety**: Compile-time checking for all remote calls
- **Swift Concurrency**: Native async/await and AsyncStream support
- **Transparent Errors**: Remote errors propagate naturally as if they were local
- **Declarative Servers**: SwiftUI-style server configuration with `@ActorBuilder`
- **Protocol Independent**: Support for gRPC or custom transports via MessageTransport protocol
- **Production Ready**: Comprehensive TLS support with certificate management

## Requirements

- Swift 6.1+
- macOS 15.0+ / iOS 18.0+ / tvOS 18.0+ / watchOS 11.0+ / visionOS 2.0+

## Installation

Add ActorEdge to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/actor-edge.git", from: "1.0.0")
]
```

## Why ActorEdge?

Traditional RPC frameworks require:
- Writing protocol definitions (`.proto` files, OpenAPI specs)
- Running code generators
- Implementing client stubs
- Managing serialization
- Handling connection lifecycle

With ActorEdge, you just write Swift:

```swift
// This is all you need to define a complete RPC interface
@Resolvable
protocol Calculator: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func add(_ a: Int, _ b: Int) async throws -> Int
}
```

The `@Resolvable` macro generates everything else.

## Quick Start

### 1. Define Your API

```swift
import ActorEdge
import Distributed

@Resolvable
public protocol Chat: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func send(_ message: String) async throws -> String
    distributed func subscribe() async throws -> AsyncStream<Message>
}

public struct Message: Codable, Sendable {
    public let id: String
    public let text: String
    public let timestamp: Date
}
```

### 2. Implement Your Server

```swift
import ActorEdge

// First, implement the distributed actor
distributed actor ChatActor: Chat {
    distributed func send(_ message: String) async throws -> String {
        return "Echo: \(message)"
    }
    
    distributed func subscribe() async throws -> AsyncStream<Message> {
        // Return your message stream
    }
}

// Then, create the server
@main
struct ChatServer: Server {
    var port: Int { 9000 }
    
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatActor(actorSystem: actorSystem)
    }
}
```

### 3. Call from Client

```swift
import ActorEdge

// That's it! The $Chat stub is auto-generated
let system = try await ActorEdgeSystem.grpcClient(endpoint: "localhost:9000")
let chat = try $Chat.resolve(id: "chat-server", using: system)

let response = try await chat.send("Hello!")
print(response) // "Echo: Hello!"
```

## Architecture

ActorEdge follows a three-module architecture:

```
YourApp/
├── SharedAPI/          # Protocol definitions
│   └── Chat.swift      # @Resolvable protocols
├── Server/            # Server implementation
│   └── main.swift     # Server with business logic
└── Client/            # Client application
    └── App.swift      # Uses generated $Protocol stubs
```

## Server Configuration

The `Server` protocol provides declarative configuration:

```swift
struct MyServer: Server {
    // Required
    var port: Int { 8080 }
    
    // Optional with defaults
    var host: String { "0.0.0.0" }
    var tls: TLSConfiguration? { nil }
    var maxConnections: Int { 1000 }
    var timeout: TimeInterval { 30 }
    
    // Define your actors
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatActor(actorSystem: actorSystem)
        UserActor(actorSystem: actorSystem)
        // Conditionally include actors
        if Config.enableMetrics {
            MetricsActor(actorSystem: actorSystem)
        }
    }
}
```

## Advanced Features

### Transport Layer

ActorEdge uses a protocol-independent transport layer:

```swift
// gRPC transport (built-in)
let system = try await ActorEdgeSystem.grpcClient(endpoint: "server:8000")

// Custom transport implementation
import ActorRuntime

class MyCustomTransport: ActorRuntime.DistributedTransport {
    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        // Implement custom transport logic
        // ...
    }

    func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Server-side response handling
        // ...
    }

    func close() async throws {
        // Cleanup resources
        // ...
    }
}

let system = ActorEdgeSystem.client(transport: MyCustomTransport())
```

### Metrics and Observability

ActorEdge includes built-in metrics for production monitoring using Swift Metrics:

```swift
import Metrics

// Configure metrics in your server
@main
struct MyServer: Server {
    var metrics: MetricsConfiguration {
        MetricsConfiguration(
            enabled: true,
            namespace: "my_app",
            labels: ["service": "api", "env": "production"]
        )
    }
}

// Available metrics:
// - actor_edge_distributed_calls_total: Total distributed calls
// - actor_edge_actor_registrations_total: Total actor registrations
// - actor_edge_actor_resolutions_total: Total actor resolutions
// - actor_edge_message_transport_latency_seconds: Transport latency
// - actor_edge_messages_envelopes_errors_total: Total envelope errors
```

You can integrate with any Swift Metrics backend (Prometheus, StatsD, etc.):

```swift
import Metrics
import Prometheus

// Bootstrap with Prometheus
let prom = PrometheusClient()
MetricsSystem.bootstrap(prom)
```

### TLS Configuration

ActorEdge provides comprehensive TLS support with flexible certificate management:

```swift
// Server TLS from files
var tls: TLSConfiguration? {
    try? TLSConfiguration.fromFiles(
        certificatePath: "/path/to/cert.pem",
        privateKeyPath: "/path/to/key.pem"
    )
}

// Server with mutual TLS
var tls: TLSConfiguration? {
    TLSConfiguration.serverMTLS(
        certificateChain: [.file("/path/to/cert.pem", format: .pem)],
        privateKey: .file("/path/to/key.pem", format: .pem),
        trustRoots: .certificates([.file("/path/to/ca.pem", format: .pem)])
    )
}

// Client with system CA certificates
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)

// Client with custom CA
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: ClientTLSConfiguration.client(
        trustRoots: .certificates([.file("/path/to/ca.pem", format: .pem)])
    )
)

// Mutual TLS client
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: ClientTLSConfiguration.mutualTLS(
        certificateChain: [.file("/path/to/client-cert.pem", format: .pem)],
        privateKey: .file("/path/to/client-key.pem", format: .pem),
        trustRoots: .certificates([.file("/path/to/ca.pem", format: .pem)])
    )
)
```

### Generics Support

ActorEdge supports generics at the **actor type level** but has limitations with **method-level generics** in `@Resolvable` protocols.

#### ✅ Supported: Generic Actor Types

You can create distributed actors with type parameters. The type is determined at actor creation time:

```swift
import ActorEdge
import Distributed

// Generic distributed actor - fully supported
distributed actor GenericStorage<T: Codable & Sendable> {
    typealias ActorSystem = ActorEdgeSystem

    private var value: T

    init(initialValue: T, actorSystem: ActorSystem) {
        self.value = initialValue
        self.actorSystem = actorSystem
    }

    distributed func get() async throws -> T {
        return value
    }

    distributed func set(_ newValue: T) async throws {
        self.value = newValue
    }
}

// Usage - type is fixed at creation
let system = ActorEdgeSystem()
let intStorage = GenericStorage(initialValue: 42, actorSystem: system)
let stringStorage = GenericStorage(initialValue: "Hello", actorSystem: system)

let number = try await intStorage.get()  // Returns Int: 42
let text = try await stringStorage.get()  // Returns String: "Hello"
```

#### ❌ Not Supported: Generic Methods in @Resolvable Protocols

**Current Limitation**: Swift 6.2's `@Resolvable` macro does not support method-level generic type parameters. Generic methods will cause runtime crashes (Signal 11).

```swift
// ❌ NOT SUPPORTED - Will crash at runtime
@Resolvable
protocol EchoService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func echo<T: Codable & Sendable>(_ value: T) async throws -> T
}
```

**Workaround**: Define separate methods for each concrete type you need:

```swift
// ✅ RECOMMENDED - Define methods for specific types
@Resolvable
protocol EchoService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func echoString(_ value: String) async throws -> String
    distributed func echoInt(_ value: Int) async throws -> Int
    distributed func echoData(_ value: Data) async throws -> Data
    distributed func echoMessage(_ value: CustomMessage) async throws -> CustomMessage
}

// Implementation
distributed actor EchoActor: EchoService {
    typealias ActorSystem = ActorEdgeSystem

    distributed func echoString(_ value: String) async throws -> String {
        return value
    }

    distributed func echoInt(_ value: Int) async throws -> Int {
        return value
    }

    distributed func echoData(_ value: Data) async throws -> Data {
        return value
    }

    distributed func echoMessage(_ value: CustomMessage) async throws -> CustomMessage {
        return value
    }
}
```

**Why This Limitation Exists**: The `@Resolvable` macro generates stub code that must call `recordGenericSubstitution()` for method-level generics. This is not currently implemented in Swift 6.2's macro expansion. This limitation may be resolved in future Swift versions.

**Best Practice**: Use generic actor types when you need type flexibility, and use specific method signatures in `@Resolvable` protocols for distributed communication.

### Error Handling

Remote errors are automatically propagated:

```swift
do {
    try await actor.someMethod()
} catch let error as ActorEdgeError {
    switch error {
    case .actorNotFound(let id):
        print("Actor \(id) not found")
    case .timeout:
        print("Request timed out")
    case .transportError(let message):
        print("Transport error: \(message)")
    default:
        print("Error: \(error)")
    }
}
```

## Testing

ActorEdge includes comprehensive test utilities using Swift Testing framework:

```swift
// Use in-memory transport for testing
let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
let system = ActorEdgeSystem(transport: clientTransport)

// Or use mock transport with response handlers
let mockTransport = MockMessageTransport()
mockTransport.setMessageHandler { envelope in
    // Return mock response
}
```

Run tests:

```bash
swift test

# Run specific test suite
swift test --filter ActorEdgeSystemTests

# Run tests by tag
swift test --filter @invocation
```

## Performance

ActorEdge is designed for real-world production use:

- **Efficient Serialization**: JSON with optional binary format support
- **Single Connection**: One HTTP/2 connection handles all actors
- **Streaming**: Native AsyncStream support for real-time data
- **Low Latency**: Minimal overhead over raw network calls
- **Type Resolution**: Optimized runtime type resolution using mangled type names

## Sample Application

Check out the [Chat Sample](Samples/) for a complete example:

```bash
# Terminal 1 - Start server
cd Samples
swift run SampleChatServer

# Terminal 2 - Run client
swift run SampleChatClient Alice
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

ActorEdge is available under the MIT license. See the LICENSE file for more info.
