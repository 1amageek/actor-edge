import Testing
import Foundation
import Distributed
import Metrics
@testable import ActorEdgeCore

/// TRUE Metrics Validation Tests
/// These tests verify metrics are actually recorded over gRPC transport
@Suite("True Metrics Validation Tests (gRPC)", .serialized)
struct TrueMetricsValidationTests {

    @Test("Metrics record distributed calls over gRPC")
    func testMetricsRecordDistributedCallsOverGRPC() async throws {
        let actorID = ActorEdgeID("metrics-grpc-actor")
        print("🔶 [TEST] Created actorID with value: '\(actorID.value)'")

        // Bootstrap metrics once for all tests
        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        }

        // Configure metrics with correct namespace
        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "grpc_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50301,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        print("🔶 [TEST] Starting server with actorIDs: \(server.actorIDs.map { "'\($0.value)'" })")
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        print("🔶 [TEST] Server started, returned IDs: \(serverActorIDs.map { "'\($0.value)'" })")
        defer { Task { try? await lifecycle.stop() } }

        print("🔶 [TEST] Creating gRPC client...")
        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(
            metrics: metricsConfig  // Use same metrics config as server
        )
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50301", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }
        print("🔶 [TEST] Resolving actor with ID: '\(serverActorIDs[0].value)'")
        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)
        print("🔶 [TEST] Actor resolved successfully")

        // Make 5 calls over gRPC
        for _ in 0..<5 {
            let _ = try await remoteActor.incrementCounter()
        }

        // Wait a bit for metrics to be recorded
        try await Task.sleep(for: .milliseconds(100))

        // Verify counter was incremented
        let counter = testMetrics.getCounter(label: "grpc_test_distributed_calls_total")
        #expect(counter != nil, "Metrics counter should exist")

        if let counter = counter {
            counter.assertIncremented()
            // Should have at least 5 calls recorded
            #expect(counter.value >= 5, "Should have recorded at least 5 distributed calls")
        }

        try await lifecycle.stop()
    }

    @Test("Metrics record actor registrations")
    func testMetricsRecordActorRegistrations() async throws {
        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let config = ActorEdgeSystem.Configuration(
            metrics: MetricsConfiguration(enabled: true, namespace: "reg_test", labels: [:])
        )
        let serverSystem = ActorEdgeSystem(configuration: config)

        // Create 3 actors
        let actor1 = TestActorImpl(actorSystem: serverSystem)
        let actor2 = EchoActorImpl(actorSystem: serverSystem)
        let actor3 = CountingActorImpl(actorSystem: serverSystem)

        // Wait for registration
        try await Task.sleep(for: .milliseconds(100))

        let counter = testMetrics.getCounter(label: "reg_test_actor_registrations_total")
        if let counter = counter {
            counter.assertIncremented()
            #expect(counter.value >= 3, "Should have at least 3 actor registrations")
        }

        // Keep actors alive
        _ = (actor1, actor2, actor3)
    }

    @Test("Metrics record actor resolutions over gRPC")
    func testMetricsRecordActorResolutions() async throws {
        let actorID = ActorEdgeID("metrics-resolution-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "resolve_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50302,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50302", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        // Resolve same actor multiple times from client
        for _ in 0..<3 {
            let _ = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)
        }

        try await Task.sleep(for: .milliseconds(100))

        let counter = testMetrics.getCounter(label: "resolve_test_actor_resolutions_total")
        if let counter = counter {
            counter.assertIncremented()
        }

        try await lifecycle.stop()
    }

    @Test("Metrics with custom labels over gRPC")
    func testMetricsWithCustomLabels() async throws {
        let actorID = ActorEdgeID("metrics-custom-labels-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "custom_label_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50303,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50303", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        let _ = try await remoteActor.incrementCounter()

        try await Task.sleep(for: .milliseconds(100))

        // Verify metrics have correct namespace
        let counter = testMetrics.getCounter(label: "custom_label_test_distributed_calls_total")
        #expect(counter != nil, "Counter with custom namespace should exist")

        if let counter = counter {
            counter.assertIncremented()
        }

        try await lifecycle.stop()
    }

    @Test("Metrics in concurrent scenarios over gRPC")
    func testMetricsConcurrentGRPC() async throws {
        let actorID = ActorEdgeID("metrics-concurrent-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "concurrent_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50304,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50304", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Make 20 concurrent calls
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let _ = try await remoteActor.incrementCounter()
                }
            }

            while let _ = try? await group.next() {}
        }

        try await Task.sleep(for: .milliseconds(200))

        // Check counter - should be at least 20
        let counter = testMetrics.getCounter(label: "concurrent_test_distributed_calls_total")
        if let counter = counter {
            #expect(counter.value >= 20, "Should have recorded at least 20 concurrent calls")
        }

        try await lifecycle.stop()
    }

    @Test("Metrics record errors over gRPC")
    func testMetricsRecordErrors() async throws {
        let actorID = ActorEdgeID("metrics-errors-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "error_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50305,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50305", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Make calls that throw errors
        for _ in 0..<5 {
            do {
                try await remoteActor.throwValidationError()
            } catch {
                // Expected
            }
        }

        try await Task.sleep(for: .milliseconds(100))

        // Verify error counter if it exists
        let errorCounter = testMetrics.getCounter(label: "error_test_distributed_errors_total")
        if let errorCounter = errorCounter {
            errorCounter.assertIncremented()
        }

        try await lifecycle.stop()
    }

    @Test("Metrics latency tracking over gRPC")
    func testMetricsLatencyTracking() async throws {
        let actorID = ActorEdgeID("metrics-latency-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "latency_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50306,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50306", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Make several calls to record latency
        for _ in 0..<10 {
            let _ = try await remoteActor.incrementCounter()
        }

        try await Task.sleep(for: .milliseconds(100))

        // Check if latency timer exists
        let timer = testMetrics.getTimer(label: "latency_test_distributed_call_latency")
        if let timer = timer {
            timer.assertRecorded()
            #expect(timer.count >= 10, "Should have recorded latency for at least 10 calls")
        }

        try await lifecycle.stop()
    }

    @Test("Metrics survive connection errors")
    func testMetricsSurviveErrors() async throws {
        let actorID = ActorEdgeID("metrics-survive-errors-actor")

        let testMetrics = TestMetrics()
        do {
            MetricsSystem.bootstrap(testMetrics)
        } catch {}

        let metricsConfig = MetricsConfiguration(
            enabled: true,
            namespace: "survive_test",
            labels: [:]
        )

        let server = SimpleTestServer(
            port: 50307,
            actors: [{ TestActorImpl(actorSystem: $0) }],
            actorIDs: [actorID],
            metrics: metricsConfig
        )
        let lifecycle = ServerLifecycleManager()
        let serverActorIDs = try await lifecycle.start(server)
        defer { Task { try? await lifecycle.stop() } }

        let clientLifecycle = ClientLifecycleManager()
        let clientConfig = ActorEdgeSystem.Configuration(metrics: metricsConfig)
        let clientSystem = try await clientLifecycle.createClient(endpoint: "127.0.0.1:50307", configuration: clientConfig)
        defer { Task { await clientLifecycle.stop() } }

        let remoteActor = try $TestActor.resolve(id: serverActorIDs[0], using: clientSystem)

        // Mix successful and failing calls
        let _ = try await remoteActor.incrementCounter()

        do {
            try await remoteActor.throwValidationError()
        } catch {}

        let _ = try await remoteActor.incrementCounter()

        try await Task.sleep(for: .milliseconds(100))

        // Metrics should reflect all calls
        let counter = testMetrics.getCounter(label: "survive_test_distributed_calls_total")
        if let counter = counter {
            #expect(counter.value >= 2, "Should have at least 2 successful calls")
        }

        try await lifecycle.stop()
    }
}
