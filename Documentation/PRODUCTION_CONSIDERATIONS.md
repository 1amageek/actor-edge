# Production Considerations for ActorEdge v1.0

**Last Updated**: 2025-11-05
**Status**: Critical review points for production deployment

This document addresses important considerations for deploying ActorEdge in production environments, based on architectural review findings.

---

## 1. Long-Running Resource Management

### Current Implementation Analysis

**Issue**: The current `grpcClient()` factory method does NOT start `runConnections()` in the background. This means:

```swift
// Current implementation in ClientFactory.swift
static func grpcClient(endpoint: String, ...) async throws -> ActorEdgeSystem {
    let grpcClient = GRPCClient(transport: clientTransport)
    let transport = GRPCTransport(client: grpcClient, ...)
    return ActorEdgeSystem(transport: transport, ...)

    // ⚠️ runConnections() is NOT called here!
}
```

**Comparison with Test Implementation**:

```swift
// Test implementation in TestServerUtilities.swift
func createClient(...) async throws -> ActorEdgeSystem {
    let grpcClient = GRPCClient(transport: clientTransport)

    // ✅ Starts runConnections() in background
    let task = Task<Void, Error> {
        try await grpcClient.runConnections()
    }
    self.runConnectionsTask = task

    // Wait for connection to establish
    try await Task.sleep(for: waitTime)

    let transport = GRPCTransport(client: grpcClient, ...)
    return ActorEdgeSystem(transport: transport, ...)
}
```

### Impact Assessment

**Severity**: 🔴 **CRITICAL**

Without `runConnections()`:
1. **Connection may not be established** - grpc-swift-2 requires explicit connection management
2. **No automatic reconnection** - Network interruptions will not trigger reconnects
3. **Resource leaks possible** - HTTP/2 connections may not be properly managed

### Recommended Solutions

#### Option 1: Add runConnections() Management to ClientFactory (Recommended)

```swift
// Enhanced ClientFactory with connection lifecycle management
public extension ActorEdgeSystem {
    /// Connection lifecycle manager for gRPC clients
    actor ConnectionManager {
        private var runConnectionsTask: Task<Void, Error>?
        private var grpcClient: GRPCClient<HTTP2ClientTransport.Posix>?

        func start(_ client: GRPCClient<HTTP2ClientTransport.Posix>) async throws {
            let task = Task<Void, Error> {
                try await client.runConnections()
            }
            self.runConnectionsTask = task
            self.grpcClient = client
        }

        func shutdown() async {
            runConnectionsTask?.cancel()
            runConnectionsTask = nil
            grpcClient = nil
        }
    }

    static func grpcClient(
        endpoint: String,
        tls: ClientTLSConfiguration? = nil,
        configuration: Configuration = .default
    ) async throws -> (ActorEdgeSystem, ConnectionManager) {
        // ... parse endpoint and create transport ...

        let grpcClient = GRPCClient(transport: clientTransport)

        // Create and start connection manager
        let connectionManager = ConnectionManager()
        try await connectionManager.start(grpcClient)

        // Wait for connection to establish
        let waitTime: Duration = (tls != nil) ? .milliseconds(2000) : .milliseconds(200)
        try await Task.sleep(for: waitTime)

        let transport = GRPCTransport(
            client: grpcClient,
            metricsNamespace: configuration.metrics.namespace
        )

        let system = ActorEdgeSystem(transport: transport, configuration: configuration)
        return (system, connectionManager)
    }
}

// Usage:
let (system, connectionManager) = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)

// ... use system ...

// Cleanup
await connectionManager.shutdown()
```

#### Option 2: Document Current Behavior and Provide ConnectionManager Separately

Add to README.md:

```markdown
### Important: Connection Lifecycle Management

The `grpcClient()` factory creates a client but does NOT start background connection
management. For production use, you MUST manage the gRPC client lifecycle:

```swift
import GRPCCore

actor ClientLifecycle {
    private var connectionTask: Task<Void, Error>?

    func connect(system: ActorEdgeSystem) async throws {
        guard let grpcTransport = system.transport as? GRPCTransport else {
            throw RuntimeError.invalidConfiguration("Not a gRPC transport")
        }

        // Access internal client (requires friend access or public API)
        connectionTask = Task {
            try await grpcTransport.client.runConnections()
        }

        try await Task.sleep(for: .milliseconds(500))
    }

    func disconnect() {
        connectionTask?.cancel()
    }
}
```

**Problem**: GRPCTransport.client is currently `private`, so this approach requires
making it accessible or providing a public connection management API.
```

### Production Testing Checklist

- [ ] **Connection Establishment**: Verify client connects successfully on startup
- [ ] **Reconnection Logic**: Test automatic reconnection after network interruption
- [ ] **Graceful Shutdown**: Ensure `runConnectionsTask.cancel()` properly closes connections
- [ ] **Memory Leaks**: Run long-duration tests (24+ hours) with periodic connection/disconnection
- [ ] **Connection Pooling**: Verify single HTTP/2 connection is reused for multiple actors
- [ ] **Concurrent Operations**: Test multiple simultaneous remote calls during connection churn
- [ ] **TLS Handshake Timing**: Measure connection establishment time with mTLS (currently 2s in tests)

### Metrics to Monitor

Add these metrics for production monitoring:

```swift
// Recommended additional metrics
actor_edge_connection_state          // Gauge: 0=disconnected, 1=connected
actor_edge_reconnection_attempts     // Counter: Total reconnection attempts
actor_edge_connection_failures       // Counter: Failed connection attempts
actor_edge_connection_duration       // Histogram: Time connected before disconnect
```

---

## 2. TLS Certificate Management

### Current Implementation

**Certificate Location**: Test certificates are stored in `Tests/ActorEdgeTests/Fixtures/`

**Generation Script**: `Tests/ActorEdgeTests/Fixtures/generate-test-certs.sh`

### Issues Identified

1. **No Production Certificate Guidance**: No documentation on production certificate lifecycle
2. **Test/Production Separation**: Test certificates could accidentally be used in production
3. **Certificate Rotation**: No strategy for certificate updates
4. **CI/CD Integration**: Certificate generation is manual

### Recommended Certificate Strategy

#### Separate Certificate Management

**Directory Structure**:
```
.
├── Tests/ActorEdgeTests/Fixtures/       # Test certificates (committed)
│   ├── generate-test-certs.sh          # Self-signed for testing
│   ├── ca-cert.pem
│   └── ...
├── .github/
│   └── workflows/
│       └── generate-test-certs.yml     # Regenerate on schedule
└── Documentation/
    └── CERTIFICATE_MANAGEMENT.md       # Production guidance
```

#### Production Certificate Documentation

Create `Documentation/CERTIFICATE_MANAGEMENT.md`:

```markdown
# Certificate Management for ActorEdge

## Production Certificates

### DO NOT use test certificates in production

Test certificates in `Tests/ActorEdgeTests/Fixtures/` are:
- Self-signed
- Committed to git (private keys exposed)
- Short validity period (30 days)
- For testing only

### Production Certificate Sources

1. **Let's Encrypt** (Free, Automated)
```swift
// Use certbot or ACME client
var tls: TLSConfiguration? {
    try? TLSConfiguration.fromFiles(
        certificatePath: "/etc/letsencrypt/live/yourdomain.com/fullchain.pem",
        privateKeyPath: "/etc/letsencrypt/live/yourdomain.com/privkey.pem"
    )
}
```

2. **Enterprise PKI** (Internal CA)
```swift
var tls: TLSConfiguration? {
    TLSConfiguration.serverMTLS(
        certificateChain: [.file("/etc/pki/tls/certs/server.pem", format: .pem)],
        privateKey: .file("/etc/pki/tls/private/server-key.pem", format: .pem),
        trustRoots: .certificates([.file("/etc/pki/tls/certs/ca-bundle.pem", format: .pem)])
    )
}
```

3. **Cloud Provider** (AWS ACM, GCP Certificate Manager)
- Load certificates from secrets management
- Rotate on schedule

### Certificate Rotation Strategy

```swift
actor CertificateReloader {
    private var currentConfig: TLSConfiguration

    func reload() async throws {
        let newConfig = try TLSConfiguration.fromFiles(
            certificatePath: "/etc/ssl/certs/server.pem",
            privateKeyPath: "/etc/ssl/private/server-key.pem"
        )

        // Update configuration atomically
        self.currentConfig = newConfig

        // Trigger server reload (requires Server protocol enhancement)
        await server.updateTLS(newConfig)
    }
}
```

**Note**: Current Server protocol does NOT support runtime certificate reload.
This requires server restart for certificate updates.
```

#### CI/CD Integration

Add `.github/workflows/test-certificates.yml`:

```yaml
name: Regenerate Test Certificates

on:
  schedule:
    # Regenerate monthly (before 30-day expiration)
    - cron: '0 0 1 * *'
  workflow_dispatch:

jobs:
  regenerate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate fresh test certificates
        run: |
          cd Tests/ActorEdgeTests/Fixtures
          ./generate-test-certs.sh

      - name: Verify certificates
        run: |
          openssl verify -CAfile Tests/ActorEdgeTests/Fixtures/ca-cert.pem \
            Tests/ActorEdgeTests/Fixtures/server-cert.pem

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v5
        with:
          title: "chore: Regenerate test certificates"
          body: "Automated regeneration of test certificates (30-day validity)"
          branch: update-test-certs
```

### Certificate Security Checklist

- [ ] **Private keys never committed to git** (production)
- [ ] **Test certificates clearly marked as test-only**
- [ ] **Certificate expiration monitoring** (alerts 7 days before expiry)
- [ ] **Separate CA for test vs production**
- [ ] **Certificate rotation procedure documented**
- [ ] **mTLS client certificate distribution strategy**
- [ ] **Certificate revocation process** (CRL or OCSP)

---

## 3. CI/CD Test Stability

### Current Test Environment Dependencies

**Identified Issues**:

1. **Port Conflicts**: Tests use fixed ports (60001-60104)
2. **Timing Sensitivity**: TLS tests require 2000ms wait time
3. **Parallel Execution**: Tests marked `.serialized` to avoid conflicts
4. **Environment-Specific**: mTLS tests depend on filesystem paths

### Recommendations

#### Make Ports Dynamic

```swift
// Instead of fixed ports
let server = SimpleTestServer(port: 60001, ...)

// Use dynamic port allocation
let server = SimpleTestServer(port: 0, ...)  // OS assigns available port
let actualPort = try await lifecycle.start(server).port
let clientSystem = try await clientLifecycle.createClient(
    endpoint: "127.0.0.1:\(actualPort)"
)
```

#### Adjust Timeouts for CI

```swift
// Add environment-based timeout configuration
extension Duration {
    static var testConnectionWait: Duration {
        if ProcessInfo.processInfo.environment["CI"] == "true" {
            // CI environments may be slower
            return .milliseconds(5000)
        } else {
            return .milliseconds(2000)
        }
    }
}

// Usage in tests
try await Task.sleep(for: .testConnectionWait)
```

#### Improve Test Isolation

```swift
@Suite("TLS Integration Tests", .serialized)  // ✅ Already done
struct TrueTLSIntegrationTests {
    // Each test uses unique port range
    static var nextPort: Int = 60000

    @Test("Successful TLS connection")
    func testTLSConnection() async throws {
        let port = Self.nextPort
        Self.nextPort += 1

        let server = SimpleTestServer(port: port, ...)
        // ...
    }
}
```

#### CI-Specific Test Configuration

Add `.github/workflows/test.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-14, ubuntu-latest]
        swift: ['6.1']

    steps:
      - uses: actions/checkout@v4

      - uses: swift-actions/setup-swift@v2
        with:
          swift-version: ${{ matrix.swift }}

      - name: Build
        run: swift build

      - name: Run Tests (with retries)
        run: |
          # Retry flaky tests up to 3 times
          for i in {1..3}; do
            swift test && break || {
              echo "Test attempt $i failed, retrying..."
              sleep 5
            }
          done

      - name: Run TLS Tests (separate, no parallelization)
        run: |
          swift test --filter TrueTLSIntegrationTests --parallel off
```

### Test Stability Checklist

- [ ] **Remove hardcoded ports** - Use OS-assigned ports
- [ ] **Add retry logic** - For transient network failures
- [ ] **Timeout tuning** - Different values for CI vs local
- [ ] **Resource cleanup** - Ensure all tests clean up properly
- [ ] **Parallel safety** - Either use `.serialized` or ensure true isolation
- [ ] **Environment detection** - Adjust behavior for CI environments
- [ ] **Flaky test identification** - Run tests 100+ times to identify intermittent failures

---

## 4. Public API Documentation

### Current Documentation Gaps

#### Issue 1: Server.actorIDs Visibility

**Current Implementation**:

```swift
public protocol Server {
    // Users may not realize they need to track actor IDs
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor]
}
```

**Problem**: No clear guidance on:
- How to assign actor IDs
- How clients discover actor IDs
- Best practices for ID management

#### Issue 2: mTLS Configuration Complexity

**Current Documentation**: Scattered across README and CLAUDE.md

**Problem**:
- Critical `requireALPN: false` setting is not prominently documented
- CA certificate vs peer certificate confusion
- No production deployment guide

#### Issue 3: Connection Lifecycle Not Documented

**Missing**: How users should manage `runConnections()` in production

### Recommended Documentation Enhancements

#### Add to README.md

**Section: "Actor ID Management"**

```markdown
### Actor ID Management

ActorEdge uses string-based actor IDs for resolution. You must coordinate IDs between
server and client.

#### Server-Side ID Assignment

```swift
@main
struct MyServer: Server {
    @ActorBuilder
    func actors(actorSystem: ActorEdgeSystem) -> [any DistributedActor] {
        // Option 1: Well-known IDs
        UserServiceActor(id: "users", actorSystem: actorSystem)
        ChatServiceActor(id: "chat", actorSystem: actorSystem)

        // Option 2: Environment-based IDs
        ServiceActor(
            id: ProcessInfo.processInfo.environment["SERVICE_ID"] ?? "default",
            actorSystem: actorSystem
        )
    }
}

// Distributed actor with custom ID
distributed actor UserServiceActor: UserService {
    init(id: String, actorSystem: ActorEdgeSystem) {
        self.actorSystem = actorSystem
        // ActorEdgeSystem will assign this specific ID
    }
}
```

#### Client-Side ID Resolution

```swift
// Hard-coded well-known IDs
let users = try $UserService.resolve(id: ActorEdgeID("users"), using: system)
let chat = try $ChatService.resolve(id: ActorEdgeID("chat"), using: system)

// Service discovery (recommended for production)
struct ServiceRegistry {
    static func discoverService(name: String) async throws -> ActorEdgeID {
        // Query service registry (Consul, etcd, etc.)
        let endpoint = try await consul.service(name)
        return ActorEdgeID(endpoint.id)
    }
}

let userServiceID = try await ServiceRegistry.discoverService(name: "users")
let users = try $UserService.resolve(id: userServiceID, using: system)
```

#### Best Practices

1. **Use well-known IDs for singleton services**: `"users"`, `"chat"`, `"notifications"`
2. **Use hierarchical IDs for scaled services**: `"region-us-west-2/users"`, `"shard-01/storage"`
3. **Implement service discovery for dynamic environments**: Kubernetes, Consul, etcd
4. **Avoid UUIDs unless necessary**: Hard to coordinate between server and client
```

#### Create Documentation/TLS_PRODUCTION_GUIDE.md

```markdown
# TLS Production Deployment Guide

## Quick Start: Production TLS

### 1. Server Configuration

```swift
@main
struct ProductionServer: Server {
    var port: Int { 443 }
    var host: String { "0.0.0.0" }

    var tls: TLSConfiguration? {
        try? TLSConfiguration.fromFiles(
            certificatePath: "/etc/ssl/certs/server.pem",
            privateKeyPath: "/etc/ssl/private/server-key.pem"
        )
    }
}
```

### 2. Client Configuration

```swift
let system = try await ActorEdgeSystem.grpcClient(
    endpoint: "api.example.com:443",
    tls: .systemDefault()
)
```

## Critical mTLS Settings

⚠️ **IMPORTANT**: mTLS requires specific configuration:

1. **`requireALPN: false`** - Default in TLSConfiguration (DO NOT CHANGE)
2. **CA certificates in trustRoots** - Not peer certificates
3. **`.noHostnameVerification`** - Required for mTLS (default)

**DO NOT**:
```swift
// ❌ Wrong - will cause handshake hang
TLSConfiguration.serverMTLS(..., requireALPN: true)

// ❌ Wrong - breaks CA validation
trustRoots: .certificates([peerCertificate])

// ❌ Wrong - requires proper DNS/IP SAN
clientCertificateVerification: .fullVerification
```

**DO**:
```swift
// ✅ Correct mTLS configuration
TLSConfiguration.serverMTLS(
    certificateChain: [.file("/etc/ssl/certs/server.pem", format: .pem)],
    privateKey: .file("/etc/ssl/private/server-key.pem", format: .pem),
    trustRoots: .certificates([.file("/etc/ssl/certs/ca.pem", format: .pem)]),
    clientCertificateVerification: .noHostnameVerification
)
```

See [CERTIFICATE_MANAGEMENT.md](CERTIFICATE_MANAGEMENT.md) for certificate lifecycle.
```

---

## Summary and Action Items

### Immediate Actions Required (Before v1.0 Release)

1. **🔴 CRITICAL**: Fix `grpcClient()` to manage `runConnections()` lifecycle
   - [ ] Implement ConnectionManager
   - [ ] Update ClientFactory.swift
   - [ ] Document lifecycle management
   - [ ] Add long-running tests (24+ hours)

2. **🟡 HIGH**: Improve certificate documentation
   - [ ] Create CERTIFICATE_MANAGEMENT.md
   - [ ] Add production certificate guidance to README
   - [ ] Implement CI certificate regeneration
   - [ ] Document test vs production separation

3. **🟡 HIGH**: Stabilize CI tests
   - [ ] Make ports dynamic
   - [ ] Add CI-specific timeouts
   - [ ] Implement test retry logic
   - [ ] Add GitHub Actions workflow

4. **🟢 MEDIUM**: Enhance API documentation
   - [ ] Document actor ID management strategy
   - [ ] Create TLS_PRODUCTION_GUIDE.md
   - [ ] Add service discovery examples
   - [ ] Document connection lifecycle

### Post-v1.0 Enhancements

- [ ] Runtime certificate reload support
- [ ] Built-in service discovery integration
- [ ] Connection health checks and metrics
- [ ] Automatic reconnection with exponential backoff
- [ ] Circuit breaker pattern for failing services

---

**Review Status**: Draft
**Next Review**: After implementing ConnectionManager
**Assigned**: Core Team
