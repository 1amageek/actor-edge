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
- **Fast by Default**: Binary serialization and HTTP/2 transport

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
    
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatActor(actorSystem: actorSystem)
    }
}
```

### 3. Call from Client

```swift
import ActorEdge

// That's it! The $Chat stub is auto-generated
let system = ActorEdgeSystem(transport: GRPCActorTransport("localhost:9000"))
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

### Binary Serialization

ActorEdge supports both JSON and binary serialization formats:

```swift
// Use binary format for better performance
let system = ActorEdgeSystem(
    transport: GRPCActorTransport(endpoint),
    encoder: BinaryInvocationEncoder.self,
    decoder: BinaryInvocationDecoder.self
)
```

### TLS Configuration

```swift
// Server TLS
var tls: TLSConfiguration? {
    .makeServerTLS(
        certificateChain: [.certificate(cert)],
        privateKey: .privateKey(key)
    )
}

// Client TLS
let transport = GRPCActorTransport(
    "api.example.com",
    tls: .makeClientTLS(trustRoots: .certificates([caCert]))
)
```

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

ActorEdge includes comprehensive test utilities:

```swift
// Use mock transport for testing
let mockTransport = MockActorTransport()
let system = ActorEdgeSystem(transport: mockTransport)

// Configure mock responses
mockTransport.mockResponse = encodedResponse
```

Run tests:

```bash
swift test
```

## Performance

ActorEdge is designed for real-world production use:

- **Binary Protocol**: ~40% smaller payload size compared to JSON
- **Single Connection**: One HTTP/2 connection handles all actors
- **Streaming**: Native AsyncStream support for real-time data
- **Low Latency**: Minimal overhead over raw network calls

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
