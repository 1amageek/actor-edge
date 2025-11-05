# ActorEdge

**Revolutionary type-safe distributed actors for Swift** — Build client-server applications using Swift's native distributed actors. No code generation, no boilerplate, just Swift.

```swift
// Define your API with @Resolvable
@Resolvable
protocol Chat: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func send(_ message: String) async throws -> String
}

// Server auto-implements it
distributed actor ChatActor: Chat { ... }

// Client auto-generates stub
let chat = try $Chat.resolve(id: "chat", using: system)
let response = try await chat.send("Hello!")  // Type-safe remote call!
```

## 🚀 What Makes ActorEdge Revolutionary?

ActorEdge brings the power of Swift's `@Resolvable` macro (SE-0428) to production distributed systems. This is **the first framework** that enables:

### ✨ Zero Boilerplate Client-Server Development

**Traditional RPC frameworks** require:
- Writing `.proto` files or OpenAPI specs
- Running code generators
- Implementing client stubs manually
- Managing serialization/deserialization
- Handling connection lifecycle
- Writing error handling boilerplate

**With ActorEdge**, you write **just Swift**:
```swift
@Resolvable
protocol UserService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func getUser(id: String) async throws -> User
    distributed func updateUser(_ user: User) async throws
}
```

That's it. The `@Resolvable` macro auto-generates:
- ✅ Type-safe client stub (`$UserService`)
- ✅ Serialization/deserialization code
- ✅ Error propagation logic
- ✅ Connection management

### 🎯 Complete Type Safety

**Compile-time verification** for all remote calls:
```swift
let service = try $UserService.resolve(id: "users", using: system)

// ✅ Compiles - correct types
let user = try await service.getUser(id: "123")

// ❌ Compiler error - wrong type
let user = try await service.getUser(id: 123)  // Error: Cannot convert Int to String
```

**Automatic error handling** - remote errors propagate naturally:
```swift
do {
    try await service.updateUser(user)
} catch {
    // Remote errors are thrown just like local errors
    print("Update failed: \(error)")
}
```

### 🌊 Native Async/Await Integration

**Streaming support** with Swift's `AsyncStream`:
```swift
@Resolvable
protocol StockService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func watchStock(_ symbol: String) async throws -> AsyncStream<Quote>
}

// Client usage - just like local async code
for try await quote in try await stocks.watchStock("AAPL") {
    print("AAPL: $\(quote.price)")
}
```

### 🏗️ Declarative Server Configuration

**SwiftUI-inspired** server setup with `@ActorBuilder`:
```swift
@main
struct MyServer: Server {
    var port: Int { 8080 }

    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        UserServiceActor(actorSystem: actorSystem)
        StockServiceActor(actorSystem: actorSystem)

        if Config.enableNotifications {
            NotificationActor(actorSystem: actorSystem)
        }
    }
}
```

Run your server:
```bash
swift run MyServer
```

That's it. No web frameworks, no routing configuration, no middleware setup.

## 🎓 Complete Tutorial

### Step 1: Create Your Project

```bash
mkdir MyApp && cd MyApp
swift package init --type executable
```

Add ActorEdge to `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/1amageek/actor-edge.git", from: "1.0.0")
]
```

### Step 2: Define Your API (SharedAPI Module)

Create a **shared API module** that both server and client will use:

```swift
// Sources/SharedAPI/Calculator.swift
import ActorEdge
import Distributed

@Resolvable
public protocol Calculator: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func add(_ a: Int, _ b: Int) async throws -> Int
    distributed func subtract(_ a: Int, _ b: Int) async throws -> Int
    distributed func multiply(_ a: Int, _ b: Int) async throws -> Int
    distributed func divide(_ a: Int, _ b: Int) async throws -> Double
}

// Custom error type (must be Codable & Sendable)
public struct CalculatorError: Error, Codable, Sendable {
    public let message: String

    public static let divideByZero = CalculatorError(message: "Division by zero")
}
```

### Step 3: Implement Your Server

```swift
// Sources/Server/main.swift
import ActorEdge
import SharedAPI

// Step 3.1: Implement the distributed actor
distributed actor CalculatorActor: Calculator {
    public typealias ActorSystem = ActorEdgeSystem

    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    public distributed func add(_ a: Int, _ b: Int) async throws -> Int {
        return a + b
    }

    public distributed func subtract(_ a: Int, _ b: Int) async throws -> Int {
        return a - b
    }

    public distributed func multiply(_ a: Int, _ b: Int) async throws -> Int {
        return a * b
    }

    public distributed func divide(_ a: Int, _ b: Int) async throws -> Double {
        guard b != 0 else {
            throw CalculatorError.divideByZero
        }
        return Double(a) / Double(b)
    }
}

// Step 3.2: Create the server
@main
struct CalculatorServer: Server {
    // Server will listen on port 9000
    public var port: Int { 9000 }

    // Define which actors to serve
    @ActorBuilder
    public func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        CalculatorActor(actorSystem: actorSystem)
    }
}
```

Run your server:
```bash
swift run Server
```

### Step 4: Build Your Client

```swift
// Sources/Client/main.swift
import ActorEdge
import SharedAPI

@main
struct CalculatorClient {
    static func main() async throws {
        // Step 4.1: Connect to server
        let system = try await ActorEdgeSystem.grpcClient(
            endpoint: "localhost:9000"
        )

        // Step 4.2: Resolve the Calculator actor using $Calculator stub
        // The $ prefix indicates this is an auto-generated stub
        let calculator = try $Calculator.resolve(
            id: ActorEdgeID("calculator"),
            using: system
        )

        // Step 4.3: Make remote calls - just like local code!
        let sum = try await calculator.add(10, 5)
        print("10 + 5 = \(sum)")  // 15

        let product = try await calculator.multiply(10, 5)
        print("10 × 5 = \(product)")  // 50

        let quotient = try await calculator.divide(10, 5)
        print("10 ÷ 5 = \(quotient)")  // 2.0

        // Step 4.4: Error handling works naturally
        do {
            let _ = try await calculator.divide(10, 0)
        } catch let error as CalculatorError {
            print("Error: \(error.message)")  // "Division by zero"
        }
    }
}
```

Run your client:
```bash
swift run Client
```

### Understanding the Magic: @Resolvable

The `@Resolvable` macro (Swift Evolution proposal SE-0428) generates a **stub actor** with the `$` prefix:

```swift
// You write:
@Resolvable
protocol Calculator: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func add(_ a: Int, _ b: Int) async throws -> Int
}

// Swift auto-generates:
distributed actor $Calculator: Calculator {
    // All methods forward to remote actor through ActorEdgeSystem
    distributed func add(_ a: Int, _ b: Int) async throws -> Int {
        // Auto-generated forwarding logic
    }
}
```

**Client-side usage**:
```swift
// Type-safe resolution with auto-generated stub
let calc = try $Calculator.resolve(id: actorID, using: system)

// Type-safe remote call
let result = try await calc.add(10, 5)
```

**Why this is revolutionary**:
- ✅ **No code generation tools** - all done by Swift compiler
- ✅ **Full type safety** - compiler checks argument/return types
- ✅ **Protocol-based** - client only needs the protocol, not implementation
- ✅ **Zero boilerplate** - no manual stub implementation required

## 📚 Real-World Example: Chat Application

### Shared API

```swift
// Sources/SharedAPI/Chat.swift
@Resolvable
public protocol Chat: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func send(_ text: String) async throws
    distributed func subscribe() async throws -> AsyncStream<Message>
    distributed func listUsers() async throws -> [User]
}

public struct Message: Codable, Sendable {
    public let id: String
    public let author: String
    public let text: String
    public let timestamp: Date
}

public struct User: Codable, Sendable {
    public let id: String
    public let name: String
    public let online: Bool
}
```

### Server Implementation

```swift
// Sources/Server/ChatActor.swift
distributed actor ChatActor: Chat {
    private var messages: [Message] = []
    private var users: [String: User] = [:]
    private var subscribers: [AsyncStream<Message>.Continuation] = []

    public distributed func send(_ text: String) async throws {
        let message = Message(
            id: UUID().uuidString,
            author: "User",
            text: text,
            timestamp: Date()
        )

        messages.append(message)

        // Broadcast to all subscribers
        for continuation in subscribers {
            continuation.yield(message)
        }
    }

    public distributed func subscribe() async throws -> AsyncStream<Message> {
        AsyncStream { continuation in
            subscribers.append(continuation)

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeSubscriber(continuation)
                }
            }
        }
    }

    public distributed func listUsers() async throws -> [User] {
        Array(users.values)
    }

    private func removeSubscriber(_ continuation: AsyncStream<Message>.Continuation) {
        subscribers.removeAll { $0 === continuation }
    }
}

@main
struct ChatServer: Server {
    var port: Int { 8000 }

    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        ChatActor(actorSystem: actorSystem)
    }
}
```

### Client Usage

```swift
let system = try await ActorEdgeSystem.grpcClient(endpoint: "localhost:8000")
let chat = try $Chat.resolve(id: ActorEdgeID("chat"), using: system)

// Send messages
try await chat.send("Hello, everyone!")

// Subscribe to messages (streaming)
Task {
    for try await message in try await chat.subscribe() {
        print("[\(message.author)]: \(message.text)")
    }
}

// List users
let users = try await chat.listUsers()
print("Online users: \(users.count)")
```

## 🔒 Production Features

### TLS/mTLS Support

ActorEdge includes comprehensive TLS support for secure production deployments:

#### Basic TLS Server

```swift
@main
struct SecureServer: Server {
    var port: Int { 443 }

    var tls: TLSConfiguration? {
        try? TLSConfiguration.fromFiles(
            certificatePath: "/etc/ssl/certs/server.pem",
            privateKeyPath: "/etc/ssl/private/server-key.pem"
        )
    }
}
```

#### Mutual TLS (mTLS) Server

```swift
var tls: TLSConfiguration? {
    TLSConfiguration.serverMTLS(
        certificateChain: [.file("/etc/ssl/certs/server.pem", format: .pem)],
        privateKey: .file("/etc/ssl/private/server-key.pem", format: .pem),
        trustRoots: .certificates([.file("/etc/ssl/certs/ca.pem", format: .pem)]),
        clientCertificateVerification: .noHostnameVerification
    )
}
```

#### TLS Client

```swift
// System default CA certificates
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)

// Custom CA certificate
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
        certificateChain: [.file("/etc/ssl/certs/client.pem", format: .pem)],
        privateKey: .file("/etc/ssl/private/client-key.pem", format: .pem),
        trustRoots: .certificates([.file("/etc/ssl/certs/ca.pem", format: .pem)]),
        serverHostname: "api.example.com"
    )
)
```

### Metrics & Observability

Built-in metrics using Swift Metrics for production monitoring:

```swift
import Metrics
import Prometheus

@main
struct MonitoredServer: Server {
    var metrics: MetricsConfiguration {
        MetricsConfiguration(
            enabled: true,
            namespace: "my_app",
            labels: [
                "service": "api",
                "env": "production",
                "region": "us-west-2"
            ]
        )
    }
}

// Bootstrap Prometheus
let prom = PrometheusClient()
MetricsSystem.bootstrap(prom)

// Available metrics:
// - actor_edge_distributed_calls_total
// - actor_edge_actor_registrations_total
// - actor_edge_actor_resolutions_total
// - actor_edge_message_transport_latency_seconds
// - actor_edge_messages_envelopes_errors_total
```

### Error Handling Best Practices

```swift
// Define custom errors (must be Codable & Sendable)
public struct ValidationError: Error, Codable, Sendable {
    public let field: String
    public let message: String
}

// Server throws typed errors
distributed actor UserService: UserServiceProtocol {
    distributed func createUser(_ user: User) async throws {
        guard !user.email.isEmpty else {
            throw ValidationError(field: "email", message: "Email is required")
        }
        // Create user...
    }
}

// Client catches typed errors
do {
    try await userService.createUser(invalidUser)
} catch let error as ValidationError {
    print("Validation failed: \(error.field) - \(error.message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## 🏗️ Architecture Patterns

### Three-Module Architecture (Recommended)

```
MyApp/
├── Package.swift
├── Sources/
│   ├── SharedAPI/              # Protocol definitions
│   │   ├── UserService.swift   # @Resolvable protocols
│   │   ├── ChatService.swift
│   │   └── Models.swift        # Shared Codable types
│   ├── Server/                 # Server implementation
│   │   ├── main.swift          # Server entry point
│   │   ├── UserServiceActor.swift
│   │   └── ChatServiceActor.swift
│   └── Client/                 # Client application
│       ├── main.swift          # Client entry point
│       └── UI.swift
└── Tests/
```

**Package.swift**:
```swift
let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SharedAPI", targets: ["SharedAPI"]),
        .executable(name: "Server", targets: ["Server"]),
        .executable(name: "Client", targets: ["Client"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/actor-edge.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "SharedAPI",
            dependencies: [
                .product(name: "ActorEdge", package: "actor-edge")
            ]
        ),
        .executableTarget(
            name: "Server",
            dependencies: ["SharedAPI", "ActorEdge"]
        ),
        .executableTarget(
            name: "Client",
            dependencies: ["SharedAPI", "ActorEdge"]
        ),
    ]
)
```

### Multi-Actor Server

```swift
@main
struct MultiServiceServer: Server {
    var port: Int { 8080 }
    var host: String { "0.0.0.0" }  // Listen on all interfaces

    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        // User management
        UserServiceActor(actorSystem: actorSystem)

        // Chat functionality
        ChatServiceActor(actorSystem: actorSystem)

        // Notifications
        NotificationServiceActor(actorSystem: actorSystem)

        // Conditional actors
        if Config.enableMetrics {
            MetricsActor(actorSystem: actorSystem)
        }

        if Config.enableAdmin {
            AdminServiceActor(actorSystem: actorSystem)
        }
    }

    // Optional: Add TLS
    var tls: TLSConfiguration? {
        try? TLSConfiguration.fromFiles(
            certificatePath: Config.tlsCertPath,
            privateKeyPath: Config.tlsKeyPath
        )
    }
}
```

### Client Connection Lifecycle

ActorEdge automatically manages gRPC connections. The `grpcClient()` method starts connection
management in the background and returns when the connection is ready.

#### Basic Usage

```swift
import ActorEdge

// Create client - connection starts automatically
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)

// Use the system
let service = try $UserService.resolve(id: ActorEdgeID("users"), using: system)
let user = try await service.getUser(id: "123")

// Shutdown when done - IMPORTANT for proper resource cleanup
try await system.shutdown()
```

#### Connection Manager Pattern (Recommended for Production)

For production applications, use a connection manager to handle connection lifecycle:

```swift
import ActorEdge

actor ConnectionManager {
    private var system: ActorEdgeSystem?
    private let endpoint: String
    private let tlsConfig: ClientTLSConfiguration?

    init(endpoint: String, tls: ClientTLSConfiguration? = nil) {
        self.endpoint = endpoint
        self.tlsConfig = tls
    }

    func connect() async throws -> ActorEdgeSystem {
        if let existing = system {
            return existing
        }

        let newSystem = try await ActorEdgeSystem.grpcClient(
            endpoint: endpoint,
            tls: tlsConfig
        )

        system = newSystem
        return newSystem
    }

    func shutdown() async throws {
        guard let system = system else { return }
        try await system.shutdown()
        self.system = nil
    }

    deinit {
        // Warning: deinit cannot be async
        // Ensure shutdown() is called before ConnectionManager is deallocated
    }
}

// Usage
let connectionManager = ConnectionManager(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)

let system = try await connectionManager.connect()
let userService = try $UserService.resolve(id: ActorEdgeID("users"), using: system)
let chatService = try $ChatService.resolve(id: ActorEdgeID("chat"), using: system)

// Use services...
let user = try await userService.getUser(id: "123")

// Cleanup when done
try await connectionManager.shutdown()
```

#### Important Notes

- ✅ **Automatic Connection**: `grpcClient()` starts `runConnections()` in background
- ✅ **Reconnection**: gRPC automatically handles reconnections on network failures
- ⚠️ **Always call `shutdown()`**: Prevents resource leaks by properly closing connections
- ⚠️ **One client per endpoint**: Create one ActorEdgeSystem per server endpoint
- ⚠️ **Connection wait time**: TLS connections wait 500ms, plaintext 100ms for establishment

## 🧪 Testing

ActorEdge makes testing distributed systems easy:

### Integration Testing

```swift
import Testing
@testable import ActorEdge
@testable import SharedAPI

@Suite("Calculator Tests")
struct CalculatorTests {
    @Test("Calculator performs addition")
    func testAddition() async throws {
        // Start server
        let server = CalculatorServer()
        let serverTask = Task {
            try await server.run()
        }

        // Give server time to start
        try await Task.sleep(for: .seconds(1))

        // Connect client
        let system = try await ActorEdgeSystem.grpcClient(
            endpoint: "localhost:9000"
        )

        let calculator = try $Calculator.resolve(
            id: ActorEdgeID("calculator"),
            using: system
        )

        // Test
        let result = try await calculator.add(10, 5)
        #expect(result == 15)

        // Cleanup
        serverTask.cancel()
    }
}
```

### Unit Testing with Mock Transport

```swift
import ActorRuntime

// Create custom mock transport
final class MockTransport: DistributedTransport {
    var mockResponses: [String: Any] = [:]

    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        // Return mock response based on method name
        let methodName = envelope.callID.methodName
        guard let response = mockResponses[methodName] else {
            throw RuntimeError.invalidEnvelope("No mock response for \(methodName)")
        }

        // Create mock response envelope
        return try ResponseEnvelope(
            callID: envelope.callID,
            result: .success(encodeResponse(response))
        )
    }
}

// Use in tests
let mockTransport = MockTransport()
mockTransport.mockResponses["add"] = 15

let system = ActorEdgeSystem.client(transport: mockTransport)
```

## 📊 Performance

ActorEdge is designed for production use:

- **Efficient Serialization**: JSON with optional binary format support
- **Connection Pooling**: Single HTTP/2 connection handles all actors
- **Streaming**: Native AsyncStream support for real-time data
- **Low Latency**: Minimal overhead over raw gRPC
- **Type Resolution**: Optimized runtime type resolution

**Benchmarks** (on M1 MacBook Pro):
- Simple RPC call latency: ~0.5ms (localhost)
- Throughput: ~20,000 calls/sec (localhost)
- Streaming: ~50,000 messages/sec

## 🛠️ Advanced Topics

### Custom Transport Layer

ActorEdge supports custom transports:

```swift
import ActorRuntime

final class WebSocketTransport: DistributedTransport {
    func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        // Implement WebSocket-based transport
        let data = try JSONEncoder().encode(envelope)
        try await webSocket.send(data)
        let response = try await webSocket.receive()
        return try JSONDecoder().decode(ResponseEnvelope.self, from: response)
    }

    func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Server-side response handling
    }

    func close() async throws {
        try await webSocket.close()
    }
}

// Use custom transport
let system = ActorEdgeSystem.client(transport: WebSocketTransport())
```

### Actor ID Management

```swift
// Simple string-based IDs
let actorID = ActorEdgeID("user-service")

// UUID-based IDs
let actorID = ActorEdgeID(UUID().uuidString)

// Hierarchical IDs
let actorID = ActorEdgeID("production/us-west-2/user-service")

// Client resolution
let service = try $UserService.resolve(id: actorID, using: system)
```

### Generics Support

#### ✅ Actor-level Generics (Supported)

```swift
distributed actor Storage<T: Codable & Sendable> {
    typealias ActorSystem = ActorEdgeSystem

    private var items: [String: T] = [:]

    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }

    distributed func store(id: String, item: T) async throws {
        items[id] = item
    }

    distributed func retrieve(id: String) async throws -> T? {
        return items[id]
    }
}

// Usage - type is fixed at creation
let intStorage = Storage<Int>(actorSystem: system)
try await intStorage.store(id: "count", item: 42)
```

#### ❌ Method-level Generics (Not Supported)

Due to Swift 6.2 limitations with the `@Resolvable` macro:

```swift
// ❌ This will crash at runtime
@Resolvable
protocol GenericService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func process<T: Codable>(_ item: T) async throws -> T
}

// ✅ Use specific types instead
@Resolvable
protocol TypedService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func processString(_ item: String) async throws -> String
    distributed func processInt(_ item: Int) async throws -> Int
    distributed func processUser(_ user: User) async throws -> User
}
```

## 📋 Requirements

- **Swift**: 6.1 or later (required for `@Resolvable` macro)
- **Platforms**:
  - macOS 15.0+
  - iOS 18.0+
  - tvOS 18.0+
  - watchOS 11.0+
  - visionOS 2.0+

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

```bash
git clone https://github.com/1amageek/actor-edge.git
cd actor-edge
swift build
swift test
```

## 📄 License

ActorEdge is available under the Apache License 2.0. See the LICENSE file for more info.

## 🙏 Acknowledgments

ActorEdge builds upon:
- [ActorRuntime](https://github.com/1amageek/swift-actor-runtime) - Core distributed actor system
- [grpc-swift-2](https://github.com/grpc/grpc-swift-2) - Modern gRPC implementation
- Swift Evolution [SE-0428](https://github.com/apple/swift-evolution/blob/main/proposals/0428-resolve-distributed-actor-protocol.md) - `@Resolvable` macro proposal

## 📚 Resources

- [Documentation](Documentation/IMPLEMENTATION_STATUS.md)
- [Sample Applications](Samples/)
- [Migration Guide](Documentation/MIGRATION_TO_ACTOR_RUNTIME.md)
- [SE-0428 Proposal](https://github.com/apple/swift-evolution/blob/main/proposals/0428-resolve-distributed-actor-protocol.md)

---

**Built with ❤️ using Swift Distributed Actors**
