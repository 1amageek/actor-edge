# ActorEdge Comprehensive Test Plan

## Overview

This document outlines the comprehensive test strategy for ActorEdge, addressing gaps identified in code review.

## Test Categories

### 1. Remote Call Integration Tests

**File**: `Tests/ActorEdgeTests/Integration/RemoteCallTests.swift`

#### Test Cases

##### 1.1 Basic Remote Call Round-Trip
- **Objective**: Verify end-to-end gRPC communication
- **Setup**:
  - Launch `ActorEdgeService` with test actors in background
  - Create `ActorEdgeSystem.grpcClient` pointing to the server
  - Use `@Resolvable` protocol to call distributed methods
- **Assertions**:
  - Remote method returns correct result
  - Data serialization/deserialization works correctly
  - Connection lifecycle is managed properly
- **Coverage**:
  - `ActorEdgeSystem.remoteCall()` with actual transport
  - `GRPCTransport.sendInvocation()` → `sendResponse()`
  - `CodableInvocationEncoder/Decoder` in real scenario
  - `DistributedActorService` method dispatch

##### 1.2 Multiple Concurrent Remote Calls
- **Objective**: Verify thread safety and concurrency handling
- **Setup**: Launch server with multiple actors
- **Test**: Issue 10+ concurrent remote calls from different tasks
- **Assertions**:
  - All calls complete successfully
  - No data corruption or race conditions
  - Connection pooling works correctly

##### 1.3 Complex Type Serialization
- **Objective**: Verify complex `Codable` types work over gRPC
- **Test Cases**:
  - Nested structs with optional fields
  - Arrays and dictionaries
  - Custom `Codable` implementations
  - Large payloads (>1MB)
- **Assertions**: Data integrity maintained across network boundary

##### 1.4 Void Method Calls
- **Objective**: Verify `remoteCallVoid()` path
- **Test**: Call methods with no return value
- **Assertions**: Execution completes without errors

##### 1.5 AsyncStream Over gRPC
- **Objective**: Verify streaming distributed methods
- **Test**: Subscribe to `AsyncStream<T>` from remote actor
- **Assertions**:
  - Stream yields multiple values
  - Cancellation propagates correctly
  - No memory leaks

---

### 2. Remote Error Path Tests

**File**: `Tests/ActorEdgeTests/Integration/ErrorPathTests.swift`

#### Test Cases

##### 2.1 Remote Actor Throws Custom Error
- **Setup**: Actor method that throws `TestError.validation("message")`
- **Assertions**:
  - Client receives `RuntimeError.executionFailed`
  - Original error message is preserved
  - Error type information is available

##### 2.2 Actor Not Found Error
- **Test**: Resolve non-existent actor ID
- **Assertions**:
  - Throws `RuntimeError.actorNotFound`
  - Error message includes actor ID

##### 2.3 Network Connection Failure
- **Test**: Stop server mid-call
- **Assertions**:
  - Throws transport error
  - Connection state is cleaned up
  - Retry logic works (if implemented)

##### 2.4 Serialization Failure
- **Test**: Send data that can't be decoded on server
- **Assertions**:
  - Throws `RuntimeError.serializationFailed`
  - Error message identifies the problematic type

##### 2.5 Timeout Handling
- **Test**: Server takes longer than configured timeout
- **Assertions**:
  - Client throws timeout error
  - Server continues processing (or is cancelled)

##### 2.6 Method Not Found
- **Test**: Call method that doesn't exist on server actor
- **Assertions**: Throws `RuntimeError.methodNotFound`

---

### 3. TLS Integration Tests

**File**: `Tests/ActorEdgeTests/Integration/TLSIntegrationTests.swift`

#### Prerequisites

Generate test certificates in `Tests/ActorEdgeTests/Fixtures/certificates/`:
```bash
# Self-signed CA
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
  -keyout ca-key.pem -out ca-cert.pem \
  -subj "/CN=Test CA"

# Server certificate
openssl req -newkey rsa:4096 -nodes \
  -keyout server-key.pem -out server-req.pem \
  -subj "/CN=localhost"
openssl x509 -req -in server-req.pem -days 365 \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem

# Client certificate (for mTLS)
openssl req -newkey rsa:4096 -nodes \
  -keyout client-key.pem -out client-req.pem \
  -subj "/CN=test-client"
openssl x509 -req -in client-req.pem -days 365 \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem
```

#### Test Cases

##### 3.1 Basic TLS Connection (Success)
- **Server Setup**:
  ```swift
  var tls: TLSConfiguration? {
      try? TLSConfiguration.fromFiles(
          certificatePath: "server-cert.pem",
          privateKeyPath: "server-key.pem"
      )
  }
  ```
- **Client Setup**:
  ```swift
  let tls = ClientTLSConfiguration.client(
      trustRoots: .certificates([.file("ca-cert.pem", format: .pem)])
  )
  let system = try await ActorEdgeSystem.grpcClient(endpoint: "localhost:9443", tls: tls)
  ```
- **Assertions**:
  - Connection established
  - Remote calls succeed
  - Data is encrypted (verify with network capture)

##### 3.2 Mutual TLS (mTLS) Success
- **Server Setup**: Require client certificates
  ```swift
  TLSConfiguration.serverMTLS(
      certificateChain: [serverCert],
      privateKey: serverKey,
      trustRoots: .certificates([caCert]),
      clientCertificateVerification: .fullVerification
  )
  ```
- **Client Setup**: Provide client certificate
  ```swift
  ClientTLSConfiguration.mutualTLS(
      certificateChain: [clientCert],
      privateKey: clientKey,
      trustRoots: .certificates([caCert])
  )
  ```
- **Assertions**: Connection succeeds with mutual authentication

##### 3.3 TLS Failure: Untrusted Certificate
- **Test**: Client connects without trusting server's CA
- **Assertions**: Connection fails with certificate verification error

##### 3.4 TLS Failure: Expired Certificate
- **Test**: Use expired certificate
- **Assertions**: Connection fails with appropriate error

##### 3.5 TLS Failure: Certificate File Not Found
- **Test**: Configure with non-existent certificate path
- **Assertions**:
  - Server initialization fails
  - Error message indicates missing file

##### 3.6 TLS Failure: Invalid Private Key
- **Test**: Certificate and key don't match
- **Assertions**: Server initialization fails

##### 3.7 mTLS Failure: Client Certificate Missing
- **Server**: Requires client certificate
- **Client**: Connects without certificate
- **Assertions**: Connection refused

##### 3.8 mTLS Failure: Untrusted Client Certificate
- **Client**: Uses certificate not signed by server's CA
- **Assertions**: Connection refused

---

### 4. Metrics Validation Tests

**File**: `Tests/ActorEdgeTests/Integration/MetricsTests.swift`

#### Setup

Use `TestMetrics` from swift-metrics for verification:
```swift
import Metrics
@testable import ActorEdgeCore

@Suite("Metrics Tests")
struct MetricsTests {
    init() {
        // Use test metrics backend
        MetricsSystem.bootstrap(TestMetrics())
    }
}
```

#### Test Cases

##### 4.1 Distributed Calls Counter
- **Test**:
  - Make 5 remote calls
  - Check `actor_edge_distributed_calls_total` counter
- **Assertions**: Counter incremented by 5

##### 4.2 Actor Registrations Counter
- **Test**:
  - Create 3 distributed actors
  - Check `actor_edge_actor_registrations_total`
- **Assertions**: Counter equals 3

##### 4.3 Actor Resolutions Counter
- **Test**:
  - Resolve same actor 3 times
  - Check `actor_edge_actor_resolutions_total`
- **Assertions**: Counter incremented by 3

##### 4.4 Transport Latency Histogram
- **Test**:
  - Make remote call through gRPC
  - Check `actor_edge_message_transport_latency_seconds`
- **Assertions**:
  - Histogram has at least 1 sample
  - Latency value is reasonable (e.g., < 1 second for local)

##### 4.5 Envelope Errors Counter
- **Test**:
  - Trigger serialization error
  - Check `actor_edge_messages_envelopes_errors_total`
- **Assertions**: Error counter incremented

##### 4.6 Metrics Labels
- **Test**: Verify labels are attached correctly
- **Assertions**:
  - Namespace is correct
  - Custom labels are present

##### 4.7 Metrics in Concurrent Scenarios
- **Test**: 20 concurrent calls from multiple tasks
- **Assertions**: All metrics are accurate (no race conditions)

---

### 5. CodableInvocationEncoder Unit Tests

**File**: `Tests/ActorEdgeTests/Unit/EncoderTests.swift`

#### Test Cases

##### 5.1 Record Target
- **Test**: `encoder.recordTarget(remoteCallTarget)`
- **Assertions**: Target identifier is stored correctly

##### 5.2 Record Generic Substitutions
- **Test**: `encoder.recordGenericSubstitution(String.self)`
- **Assertions**: Type name is recorded (for future Swift support)

##### 5.3 Record Multiple Arguments in Order
- **Test**: Record `(String, Int, Bool)`
- **Assertions**: Arguments maintain order in envelope

##### 5.4 Make Invocation Envelope
- **Test**: Create envelope after recording
- **Assertions**:
  - Envelope contains correct recipient ID
  - Target is set
  - Arguments are encoded
  - Envelope is `Codable`

##### 5.5 Encoder State Machine
- **Test**: Try to record after `doneRecording()`
- **Assertions**: Throws error

##### 5.6 Round-Trip with Decoder
- **Test**: Encode arguments, decode them back
- **Assertions**: Values match exactly

---

### 6. @Resolvable Limitation Regression Test

**File**: `Tests/ActorEdgeTests/Regression/GenericLimitationTests.swift`

#### Test Cases

##### 6.1 Generic Method Known Failure
```swift
@Test("Generic method limitation - Skip until Swift fixes @Resolvable",
      .disabled("Swift 6.2 @Resolvable macro does not support generic methods"))
func testGenericMethodKnownLimitation() async throws {
    // This test documents the known limitation
    // When Swift fixes the @Resolvable macro, remove .disabled and verify it works

    @Resolvable
    protocol GenericEcho: DistributedActor where ActorSystem == ActorEdgeSystem {
        distributed func echo<T: Codable & Sendable>(_ value: T) async throws -> T
    }

    distributed actor GenericEchoImpl: GenericEcho {
        typealias ActorSystem = ActorEdgeSystem

        distributed func echo<T: Codable & Sendable>(_ value: T) async throws -> T {
            return value
        }
    }

    let system = ActorEdgeSystem()
    let actor = GenericEchoImpl(actorSystem: system)
    let resolved = try $GenericEcho.resolve(id: actor.id, using: system)

    // This SHOULD work but currently crashes with Signal 11
    let result: String = try await resolved.echo("test")
    #expect(result == "test")
}
```

##### 6.2 Generic Actor Type Success
```swift
@Test("Generic actor types work correctly")
func testGenericActorType() async throws {
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
    }

    let system = ActorEdgeSystem()
    let storage = GenericStorage(initialValue: 42, actorSystem: system)
    let result = try await storage.get()

    #expect(result == 42)
}
```

---

## Test Execution Strategy

### Local Development
```bash
# Run all tests
swift test

# Run specific category
swift test --filter Integration
swift test --filter Unit
swift test --filter Regression

# Run specific test
swift test --filter testBasicRemoteCallRoundTrip
```

### CI/CD Pipeline
```yaml
# .github/workflows/test.yml
jobs:
  unit-tests:
    runs-on: macos-15
    steps:
      - run: swift test --filter Unit

  integration-tests:
    runs-on: macos-15
    steps:
      - run: swift test --filter Integration

  regression-tests:
    runs-on: macos-15
    steps:
      - run: swift test --filter Regression
```

### Coverage Requirements
- **Unit Tests**: >90% line coverage
- **Integration Tests**: All critical paths (remote calls, TLS, errors)
- **Regression Tests**: Document known limitations

---

## Implementation Priority

### Phase 1: Critical (High Priority)
1. ✅ Remote call round-trip integration tests
2. ✅ Remote error path tests
3. ✅ Metrics validation tests

### Phase 2: Important (Medium Priority)
4. ✅ TLS integration tests (success cases)
5. ✅ TLS failure scenario tests
6. ✅ CodableInvocationEncoder unit tests

### Phase 3: Documentation (Low Priority)
7. ✅ @Resolvable limitation regression test

---

## Test Utilities Required

### TestServer Helper
```swift
actor TestServer {
    private var service: GRPCServer?

    func start(port: Int, actors: [any DistributedActor], tls: TLSConfiguration? = nil) async throws
    func stop() async throws
    var isRunning: Bool { get }
}
```

### Certificate Generator
```swift
struct CertificateGenerator {
    static func generateSelfSigned() throws -> (cert: Data, key: Data)
    static func generateCA() throws -> (cert: Data, key: Data)
    static func generateSigned(ca: Data, caKey: Data) throws -> (cert: Data, key: Data)
}
```

### Metrics Assertions
```swift
extension TestMetrics {
    func assertCounter(_ name: String, equals value: Int64)
    func assertHistogram(_ name: String, hasRecorded: Bool)
}
```

---

## Success Criteria

- [ ] All Phase 1 tests implemented and passing
- [ ] All Phase 2 tests implemented and passing
- [ ] Phase 3 regression test documented
- [ ] Test coverage >85%
- [ ] CI/CD pipeline includes all test categories
- [ ] Documentation updated with test examples

---

## References

- Swift Testing: https://github.com/swiftlang/swift-testing
- swift-metrics: https://github.com/apple/swift-metrics
- grpc-swift: https://github.com/grpc/grpc-swift
- ActorRuntime: https://github.com/1amageek/swift-actor-runtime
