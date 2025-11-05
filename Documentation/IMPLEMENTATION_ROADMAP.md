# ActorEdge Implementation Roadmap

## Overview

This document outlines the implementation plan for completing ActorEdge v1.0 after the ActorRuntime 0.2.0 integration and comprehensive cleanup.

**Current Status** (2025-11-05):
- ✅ Core functionality: Complete
- ✅ ActorRuntime integration: Complete
- ✅ Code cleanup: 472 lines removed
- ✅ Build: Clean (0 warnings, 0 errors)
- ✅ Tests: 10/10 passing
- 🚧 TLS: API designed, implementation pending
- 🚧 Metrics: 2/5 implemented
- ❌ Tracing: Placeholder only, to be removed

## Phase 1: Cleanup (Immediate)

**Goal**: Remove non-functional placeholders and unused code

**Priority**: HIGH
**Estimated Time**: 1-2 hours
**Risk**: LOW (removal only, no new code)

### Task 1.1: Remove TracingConfiguration

**Files to Modify**:
```
DELETE: Sources/ActorEdgeCore/Configuration/TracingConfiguration.swift
MODIFY: Sources/ActorEdgeCore/Protocols/Server.swift (remove tracing property)
MODIFY: Sources/ActorEdgeCore/ActorEdgeSystem.swift (remove from Configuration)
MODIFY: Package.swift (optionally remove swift-distributed-tracing dependency)
```

**Changes**:
```swift
// Server.swift - REMOVE
var tracing: TracingConfiguration { get }

// Server.swift extension - REMOVE
var tracing: TracingConfiguration { .default }

// ActorEdgeSystem.swift Configuration - REMOVE
public let tracing: TracingConfiguration

// ActorEdgeSystem.swift init - REMOVE parameter
tracing: TracingConfiguration = .disabled,
```

**Testing**:
- ✅ Verify build succeeds
- ✅ Verify all tests pass
- ✅ Check no references remain: `grep -r "TracingConfiguration\|\.tracing"`

**Breaking Change**: YES (removes public API)
**Mitigation**: Unlikely anyone is using this placeholder

### Task 1.2: Remove Certificate Validation Placeholders

**Files to Modify**:
```
MODIFY: Sources/ActorEdgeCore/Utilities/CertificateUtilities.swift
```

**Changes**:
```swift
// DELETE these methods:
public static func isCertificateValid(_ certificate: NIOSSLCertificate) -> Bool
public static func commonName(from certificate: NIOSSLCertificate) -> String?

// KEEP these methods:
public static func loadCertificateChain(from path: String) throws -> [NIOSSLCertificate]
public static func loadPrivateKey(...) throws -> NIOSSLPrivateKey
public static func serverConfig(...) throws -> TLSConfiguration
public static func clientConfig(...) throws -> ClientTLSConfiguration
```

**Testing**:
- ✅ Verify build succeeds
- ✅ Verify tests pass
- ✅ Check no usages: `grep -r "isCertificateValid\|commonName"`

**Breaking Change**: YES (removes public API)
**Mitigation**: Methods were non-functional, unlikely in use

---

## Phase 2: TLS Implementation (HIGH Priority)

**Goal**: Enable secure gRPC connections with full TLS support

**Priority**: HIGH
**Estimated Time**: 4-6 hours
**Risk**: MEDIUM (integration with grpc-swift APIs)

### Task 2.1: Implement Server-Side TLS

**Files to Modify**:
```
MODIFY: Sources/ActorEdgeServer/ActorEdgeService.swift (lines 86-99)
ADD: Sources/ActorEdgeCore/Configuration/TLSConfiguration+NIOSSL.swift (new file)
```

**Implementation**:

1. **Create TLS mapping extension** (`TLSConfiguration+NIOSSL.swift`):
```swift
import NIOSSL
import Foundation

extension TLSConfiguration {
    /// Convert ActorEdge TLSConfiguration to NIOSSL TLSConfiguration
    func toNIOSSL() throws -> NIOSSL.TLSConfiguration {
        var tlsConfig = NIOSSL.TLSConfiguration.makeServerConfiguration(
            certificateChain: try certificateChain.map { try $0.toNIOSSLCertificate() },
            privateKey: try privateKey.toNIOSSLPrivateKey()
        )

        // Apply trust roots if specified
        if let trustRoots = self.trustRoots {
            tlsConfig.trustRoots = try .certificates(trustRoots.map { try $0.toNIOSSLCertificate() })
        }

        // Apply verification mode
        tlsConfig.certificateVerification = clientCertificateVerification

        return tlsConfig
    }
}

extension CertificateSource {
    func toNIOSSLCertificate() throws -> NIOSSLCertificate {
        switch self {
        case .bytes(let data, let format):
            return try NIOSSLCertificate(bytes: Array(data), format: format.toNIOSSL())
        case .file(let path, let format):
            return try NIOSSLCertificate(file: path, format: format.toNIOSSL())
        case .certificate(let cert):
            return cert
        }
    }
}

extension PrivateKeySource {
    func toNIOSSLPrivateKey() throws -> NIOSSLPrivateKey {
        switch self {
        case .bytes(let data, let format, let passphrase):
            return try NIOSSLPrivateKey(
                bytes: Array(data),
                format: format.toNIOSSL(),
                passphraseCallback: passphrase.map { pwd in { _ in pwd.utf8 } }
            )
        case .file(let path, let format, let passphrase):
            return try NIOSSLPrivateKey(
                file: path,
                format: format.toNIOSSL(),
                passphraseCallback: passphrase.map { pwd in { _ in pwd.utf8 } }
            )
        case .privateKey(let key):
            return key
        }
    }
}

extension CertificateFormat {
    func toNIOSSL() -> NIOSSL.NIOSSLSerializationFormats {
        switch self {
        case .pem: return .pem
        case .der: return .der
        }
    }
}
```

2. **Update ActorEdgeService.swift**:
```swift
// Replace lines 86-99
let transportConfig: HTTP2ServerTransport.Posix
if let tlsConfig = configuration.server.tls {
    logger.info("Configuring TLS for gRPC server")

    let niosslConfig = try tlsConfig.toNIOSSL()

    transportConfig = HTTP2ServerTransport.Posix(
        address: .ipv4(host: host, port: port),
        transportSecurity: .tls(
            config: .defaults { config in
                config = niosslConfig
            }
        )
    )

    logger.info("TLS configured successfully")
} else {
    logger.info("Using plaintext (no TLS)")

    transportConfig = HTTP2ServerTransport.Posix(
        address: .ipv4(host: host, port: port),
        transportSecurity: .plaintext
    )
}
```

**Testing**:
- Unit test: TLS configuration mapping
- Integration test: Server with self-signed certificate
- Integration test: Client connection to TLS server

### Task 2.2: Implement Client-Side TLS

**Files to Modify**:
```
MODIFY: Sources/ActorEdgeClient/ClientFactory.swift
ADD: Sources/ActorEdgeCore/Configuration/ClientTLSConfiguration+NIOSSL.swift
```

**Implementation**:

1. **Create client TLS mapping** (`ClientTLSConfiguration+NIOSSL.swift`):
```swift
import NIOSSL

extension ClientTLSConfiguration {
    func toNIOSSL() throws -> NIOSSL.TLSConfiguration {
        var tlsConfig = NIOSSL.TLSConfiguration.makeClientConfiguration()

        // Set trust roots
        switch trustRoots {
        case .systemDefault:
            tlsConfig.trustRoots = .default
        case .certificates(let sources):
            tlsConfig.trustRoots = try .certificates(sources.map { try $0.toNIOSSLCertificate() })
        case .file(let path):
            tlsConfig.trustRoots = .file(path)
        }

        // Add client certificates for mTLS if provided
        if let certChain = certificateChain, let key = privateKey {
            tlsConfig.certificateChain = try certChain.map { try $0.toNIOSSLCertificate() }
                .map { .certificate($0) }
            tlsConfig.privateKey = try .privateKey(key.toNIOSSLPrivateKey())
        }

        return tlsConfig
    }
}
```

2. **Update ClientFactory.swift**:
```swift
// Add TLS parameter to grpcClient method
public static func grpcClient(
    endpoint: String,
    tls: ClientTLSConfiguration? = nil,  // NEW parameter
    configuration: Configuration = .default
) async throws -> ActorEdgeSystem {
    // ... parse endpoint ...

    let clientTransport: HTTP2ClientTransport.Posix

    if let tlsConfig = tls {
        let niosslConfig = try tlsConfig.toNIOSSL()

        clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: .tls(
                config: .defaults { config in
                    config = niosslConfig
                }
            )
        )
    } else {
        clientTransport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: .plaintext
        )
    }

    let grpcClient = GRPCClient(transport: clientTransport)
    let transport = GRPCTransport(client: grpcClient)

    return ActorEdgeSystem(transport: transport, configuration: configuration)
}
```

**Testing**:
- Unit test: Client TLS configuration mapping
- Integration test: Client connecting to TLS server
- Integration test: Mutual TLS (mTLS) authentication

### Task 2.3: Add TLS Integration Tests

**Files to Add**:
```
ADD: Tests/ActorEdgeTests/Integration/TLSTests.swift
ADD: Tests/ActorEdgeTests/Fixtures/test-certificates/ (test certs)
```

**Test Coverage**:
1. Server with TLS, plaintext client (should fail)
2. Server with TLS, TLS client with system roots
3. Server with TLS, TLS client with custom CA
4. Mutual TLS (client and server certificates)
5. Invalid certificate handling
6. Certificate chain validation

---

## Phase 3: Metrics Implementation (MEDIUM Priority)

**Goal**: Complete observability metrics for production monitoring

**Priority**: MEDIUM
**Estimated Time**: 3-4 hours
**Risk**: LOW (additive changes, existing framework)

### Task 3.1: Implement Actor Lifecycle Metrics

**Files to Modify**:
```
MODIFY: Sources/ActorEdgeCore/ActorEdgeSystem.swift
MODIFY: Sources/ActorEdgeCore/Configuration/MetricsConfiguration.swift
```

**Implementation**:

1. **Add metric names** (`MetricsConfiguration.swift`):
```swift
public struct MetricNames: Sendable {
    // Existing
    public let distributedCallsTotal: String
    public let methodInvocationsTotal: String

    // NEW
    public let actorRegistrationsTotal: String
    public let actorResolutionsTotal: String
    public let actorResignationsTotal: String

    public init(namespace: String) {
        self.distributedCallsTotal = "\(namespace)_distributed_calls_total"
        self.methodInvocationsTotal = "\(namespace)_method_invocations_total"
        self.actorRegistrationsTotal = "\(namespace)_actor_registrations_total"
        self.actorResolutionsTotal = "\(namespace)_actor_resolutions_total"
        self.actorResignationsTotal = "\(namespace)_actor_resignations_total"
    }
}
```

2. **Add counters** (`ActorEdgeSystem.swift`):
```swift
// Add to ActorEdgeSystem class
private let actorRegistrationsCounter: Counter
private let actorResolutionsCounter: Counter
private let actorResignationsCounter: Counter

// Initialize in init methods
self.actorRegistrationsCounter = Counter(label: metricNames.actorRegistrationsTotal)
self.actorResolutionsCounter = Counter(label: metricNames.actorResolutionsTotal)
self.actorResignationsCounter = Counter(label: metricNames.actorResignationsTotal)

// Increment in actorReady()
public func actorReady<Act>(_ actor: Act) where Act: DistributedActor {
    actorRegistrationsCounter.increment()  // NEW
    logger.info("Actor ready", ...)
    ...
}

// Increment in resolve()
public func resolve<Act>(id: ActorID, as actorType: Act.Type) throws -> Act? {
    actorResolutionsCounter.increment()  // NEW
    ...
}

// Increment in resignID()
public func resignID(_ id: ActorID) {
    actorResignationsCounter.increment()  // NEW
    logger.debug("Actor resigned", ...)
    ...
}
```

**Testing**:
- Unit test: Verify counters increment
- Integration test: Register multiple actors, check count

### Task 3.2: Implement Transport Latency Metrics

**Files to Modify**:
```
MODIFY: Sources/ActorEdgeCore/Transport/GRPCTransport.swift
MODIFY: Sources/ActorEdgeCore/Configuration/MetricsConfiguration.swift
```

**Implementation**:

1. **Add metric name**:
```swift
// MetricsConfiguration.swift
public let transportLatencySeconds: String

public init(namespace: String) {
    ...
    self.transportLatencySeconds = "\(namespace)_transport_latency_seconds"
}
```

2. **Add histogram** (`GRPCTransport.swift`):
```swift
import Metrics

public final class GRPCTransport: DistributedTransport, Sendable {
    private let client: GRPCClient
    private let logger: Logger
    private let latencyHistogram: Histogram  // NEW

    public init(client: GRPCClient, metricsNamespace: String = "actor_edge") {
        self.client = client
        self.logger = Logger(label: "ActorEdge.GRPCTransport")

        let metricNames = MetricNames(namespace: metricsNamespace)
        self.latencyHistogram = Histogram(label: metricNames.transportLatencySeconds)
    }

    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        let startTime = ContinuousClock.now  // NEW

        logger.trace("Sending invocation: \(envelope.callID)")

        let response: ResponseEnvelope = try await client.unary(
            request: ClientRequest(message: envelope),
            descriptor: method,
            serializer: JSONSerializer<InvocationEnvelope>(),
            deserializer: JSONDeserializer<ResponseEnvelope>(),
            options: .defaults
        ) { response in
            return try response.message
        }

        // Record latency
        let duration = startTime.duration(to: ContinuousClock.now)
        latencyHistogram.record(duration.timeInterval)  // NEW

        logger.trace("Received response: \(response.callID)")

        return response
    }
    ...
}
```

**Testing**:
- Unit test: Verify histogram records values
- Integration test: Make calls, check latency metrics

### Task 3.3: Add Metrics Integration Tests

**Files to Add**:
```
ADD: Tests/ActorEdgeTests/Integration/MetricsTests.swift
```

**Test Coverage**:
1. Actor registration counter increments
2. Actor resolution counter increments
3. Actor resignation counter increments
4. Distributed call counter increments
5. Method invocation counter increments
6. Transport latency histogram records
7. Multiple concurrent operations don't lose counts

---

## Phase 4: Documentation Update (Final)

**Goal**: Ensure documentation matches implementation

**Priority**: HIGH
**Estimated Time**: 2-3 hours
**Risk**: LOW (documentation only)

### Task 4.1: Update CLAUDE.md

**Changes Needed**:
1. Remove references to removed features (TracingConfiguration, certificate validation)
2. Update implementation status section
3. Add TLS implementation details
4. Update metrics implementation status
5. Clarify ActorRuntime role

### Task 4.2: Update README.md

**Changes Needed**:
1. Add TLS usage examples
2. Add metrics configuration examples
3. Update feature list
4. Add production deployment guide

### Task 4.3: Create Migration Guide

**File to Create**:
```
ADD: Documentation/MIGRATION_GUIDE.md
```

**Content**:
- Breaking changes from cleanup
- How to migrate from tracing placeholder
- TLS configuration migration (if any old format existed)

---

## Testing Strategy

### Unit Tests (Per Feature)
- TLS configuration mapping
- Metrics counter increments
- Error handling

### Integration Tests (End-to-End)
- TLS server and client communication
- Metrics collection accuracy
- Actor lifecycle with metrics

### Manual Testing Checklist
- [ ] Server starts with TLS
- [ ] Client connects via TLS
- [ ] mTLS authentication works
- [ ] Metrics are exported correctly
- [ ] Invalid certificates are rejected
- [ ] Plaintext still works

---

## Release Criteria for v1.0

### Must Have (Blocking)
- ✅ ActorRuntime integration complete
- ✅ Clean build (0 warnings)
- ✅ All tests passing
- ⏳ TLS implementation complete
- ⏳ Core metrics complete
- ⏳ Documentation updated

### Nice to Have (Non-Blocking)
- Additional metrics (request size, error rates)
- Performance benchmarks
- Example applications
- Docker deployment guide

---

## Risk Assessment

### High Risk Items
1. **TLS Integration**: Requires correct NIOSSL API usage
   - Mitigation: Thorough testing with various certificate configurations
   - Fallback: Keep plaintext as default

2. **Breaking Changes**: Removing TracingConfiguration, certificate validation
   - Mitigation: Unlikely anyone using these placeholders
   - Communication: Clear migration guide

### Medium Risk Items
1. **Metrics Overhead**: Performance impact of metrics collection
   - Mitigation: Metrics are optional, can be disabled
   - Testing: Performance benchmarks

### Low Risk Items
1. **Documentation**: No code risk
2. **Additive Metrics**: Backward compatible

---

## Timeline Estimate

### Conservative Estimate (Single Developer)
- **Phase 1 (Cleanup)**: 2 hours
- **Phase 2 (TLS)**: 6 hours
- **Phase 3 (Metrics)**: 4 hours
- **Phase 4 (Documentation)**: 3 hours
- **Testing & Refinement**: 5 hours
- **Total**: ~20 hours (2.5 working days)

### Optimistic Estimate
- **Total**: ~12 hours (1.5 working days)

---

## Success Metrics

### Code Quality
- ✅ 0 build warnings
- ✅ 0 critical issues
- ✅ All tests passing
- ✅ Code coverage > 80% for new code

### Feature Completeness
- ✅ TLS working (server + client + mTLS)
- ✅ All 5 core metrics implemented
- ✅ Documentation complete

### Performance
- No significant latency increase with TLS
- Metrics overhead < 1% of request time

---

## Next Steps

1. **Review this roadmap** with team/stakeholders
2. **Approve design decisions** in DESIGN_DECISIONS.md
3. **Begin Phase 1** (cleanup) immediately
4. **Implement Phase 2** (TLS) as priority
5. **Complete Phase 3** (metrics) for observability
6. **Finalize Phase 4** (documentation) before release

---

**Document Status**: Draft
**Last Updated**: 2025-11-05
**Author**: Claude Code
**Review Status**: Pending
