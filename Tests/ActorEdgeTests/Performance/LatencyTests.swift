import Testing
import Foundation
import Distributed
@testable import ActorEdgeCore
@testable import ActorEdgeServer
@testable import ActorEdgeClient

// MARK: - Test Types

struct ComplexInput: Codable, Sendable {
    let id: UUID
    let data: [String: Int]
    let timestamp: Date
}

struct ComplexOutput: Codable, Sendable {
    let processedId: UUID
    let result: Int
    let processingTime: TimeInterval
}

// MARK: - Test Actors

@Resolvable
protocol LatencyTestService: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func ping() async throws
    distributed func echo(_ value: Int) async throws -> Int
    distributed func processWithDelay(_ data: Data, delayMS: Int) async throws -> Int
    distributed func complexOperation(_ input: ComplexInput) async throws -> ComplexOutput
}

distributed actor LatencyTestActor: LatencyTestService {
    public typealias ActorSystem = ActorEdgeSystem
    
    init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    distributed func ping() async throws {
        // No-op, just measuring round-trip time
    }
    
    distributed func echo(_ value: Int) async throws -> Int {
        return value
    }
    
    distributed func processWithDelay(_ data: Data, delayMS: Int) async throws -> Int {
        try await Task.sleep(for: .milliseconds(delayMS))
        return data.count
    }
    
    distributed func complexOperation(_ input: ComplexInput) async throws -> ComplexOutput {
        let start = ContinuousClock.now
        
        // Simulate some processing
        var sum = 0
        for (_, value) in input.data {
            sum += value
        }
        
        let processingTime = start.duration(to: ContinuousClock.now).timeInterval
        
        return ComplexOutput(
            processedId: input.id,
            result: sum,
            processingTime: processingTime
        )
    }
}

/// Performance test suite for measuring latency
@Suite("Latency Performance Tests", .tags(.performance))
struct LatencyTests {
    
    // MARK: - Test Configuration
    
    /// Configuration for latency tests
    struct LatencyConfiguration {
        let iterations: Int
        let acceptableLatencyMS: Double
        let acceptableP99LatencyMS: Double
        
        static let fast = LatencyConfiguration(
            iterations: 100,
            acceptableLatencyMS: 10.0,
            acceptableP99LatencyMS: 20.0
        )
        
        static let standard = LatencyConfiguration(
            iterations: 1000,
            acceptableLatencyMS: 20.0,
            acceptableP99LatencyMS: 50.0
        )
        
        static let stress = LatencyConfiguration(
            iterations: 5000,
            acceptableLatencyMS: 50.0,
            acceptableP99LatencyMS: 100.0
        )
    }
    
    /// Structure to hold latency statistics
    struct LatencyStats {
        let min: Double
        let max: Double
        let mean: Double
        let median: Double
        let p95: Double
        let p99: Double
        let stdDev: Double
        
        init(latencies: [Double]) {
            let sorted = latencies.sorted()
            self.min = sorted.first ?? 0
            self.max = sorted.last ?? 0
            self.mean = latencies.reduce(0, +) / Double(latencies.count)
            
            // Median
            let midIndex = sorted.count / 2
            if sorted.count % 2 == 0 {
                self.median = (sorted[midIndex - 1] + sorted[midIndex]) / 2
            } else {
                self.median = sorted[midIndex]
            }
            
            // Percentiles
            let p95Index = Int(Double(sorted.count) * 0.95)
            let p99Index = Int(Double(sorted.count) * 0.99)
            self.p95 = sorted[Swift.min(p95Index, sorted.count - 1)]
            self.p99 = sorted[Swift.min(p99Index, sorted.count - 1)]
            
            // Standard deviation
            let meanValue = self.mean  // Capture mean value
            let variance = latencies.reduce(0) { sum, latency in
                sum + pow(latency - meanValue, 2)
            } / Double(latencies.count)
            self.stdDev = sqrt(variance)
        }
        
        func summary() -> String {
            return """
            Latency Statistics (ms):
              Min: \(String(format: "%.2f", min))
              Max: \(String(format: "%.2f", max))
              Mean: \(String(format: "%.2f", mean))
              Median: \(String(format: "%.2f", median))
              P95: \(String(format: "%.2f", p95))
              P99: \(String(format: "%.2f", p99))
              StdDev: \(String(format: "%.2f", stdDev))
            """
        }
    }
    
    // MARK: - Latency Tests
    
    @Test("Simple ping latency")
    func testSimplePingLatency() async throws {
        let config = LatencyConfiguration.fast
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        
        // Wait for actor registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Get client reference
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        // Warmup
        for _ in 0..<10 {
            try await clientRef.ping()
        }
        
        // Measure latencies
        var latencies: [Double] = []
        
        for _ in 0..<config.iterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            try await clientRef.ping()
            let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            latencies.append(latencyMS)
        }
        
        let stats = LatencyStats(latencies: latencies)
        print("Ping latency: \(stats.summary())")
        
        #expect(stats.mean <= config.acceptableLatencyMS,
                "Mean latency \(stats.mean)ms should be <= \(config.acceptableLatencyMS)ms")
        #expect(stats.p99 <= config.acceptableP99LatencyMS,
                "P99 latency \(stats.p99)ms should be <= \(config.acceptableP99LatencyMS)ms")
    }
    
    @Test("Echo operation latency")
    func testEchoLatency() async throws {
        let config = LatencyConfiguration.standard
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        // Warmup
        for i in 0..<10 {
            let result = try await clientRef.echo(i)
            #expect(result == i)
        }
        
        // Measure latencies
        var latencies: [Double] = []
        
        for i in 0..<config.iterations {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try await clientRef.echo(i)
            let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            #expect(result == i)
            latencies.append(latencyMS)
            
            // Yield periodically
            if i % 100 == 0 {
                await Task.yield()
            }
        }
        
        let stats = LatencyStats(latencies: latencies)
        print("Echo latency: \(stats.summary())")
        
        #expect(stats.mean <= config.acceptableLatencyMS)
        #expect(stats.p99 <= config.acceptableP99LatencyMS)
    }
    
    @Test("Complex operation latency")
    func testComplexOperationLatency() async throws {
        let config = LatencyConfiguration.standard
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        var latencies: [Double] = []
        
        for i in 0..<config.iterations {
            let input = ComplexInput(
                id: UUID(),
                data: [
                    "value1": i,
                    "value2": i * 2,
                    "value3": i * 3
                ],
                timestamp: Date()
            )
            
            let startTime = CFAbsoluteTimeGetCurrent()
            let output = try await clientRef.complexOperation(input)
            let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            
            #expect(output.processedId == input.id)
            #expect(output.result == i * 6) // 1 + 2 + 3 = 6
            
            latencies.append(latencyMS)
        }
        
        let stats = LatencyStats(latencies: latencies)
        print("Complex operation latency: \(stats.summary())")
        
        // Complex operations can have higher latency
        #expect(stats.mean <= config.acceptableLatencyMS * 2)
        #expect(stats.p99 <= config.acceptableP99LatencyMS * 2)
    }
    
    @Test("Latency under load")
    func testLatencyUnderLoad() async throws {
        let config = LatencyConfiguration.stress
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        // Create background load
        let loadTask = Task {
            for i in 0..<1000 {
                try? await clientRef.echo(i)
                if Task.isCancelled { break }
            }
        }
        
        // Measure latencies under load
        var latencies: [Double] = []
        
        for _ in 0..<100 { // Reduced iterations for load test
            let startTime = CFAbsoluteTimeGetCurrent()
            try await clientRef.ping()
            let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            latencies.append(latencyMS)
            
            await Task.yield()
        }
        
        loadTask.cancel()
        
        let stats = LatencyStats(latencies: latencies)
        print("Latency under load: \(stats.summary())")
        
        // Under load, latency can be higher
        #expect(stats.mean <= config.acceptableLatencyMS)
        #expect(stats.p99 <= config.acceptableP99LatencyMS)
    }
    
    @Test("Latency with varying payload sizes")
    func testLatencyWithVaryingPayloads() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        let payloadSizes = [100, 1024, 10240, 102400] // 100B, 1KB, 10KB, 100KB
        
        for size in payloadSizes {
            let payload = Data(repeating: 0x42, count: size)
            var latencies: [Double] = []
            
            // Warmup
            for _ in 0..<5 {
                _ = try await clientRef.processWithDelay(payload, delayMS: 0)
            }
            
            // Measure
            for _ in 0..<50 {
                let startTime = CFAbsoluteTimeGetCurrent()
                let result = try await clientRef.processWithDelay(payload, delayMS: 0)
                let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                
                #expect(result == size)
                latencies.append(latencyMS)
            }
            
            let stats = LatencyStats(latencies: latencies)
            print("Payload size \(size) bytes: \(stats.summary())")
            
            // Larger payloads should still maintain reasonable latency
            #expect(stats.mean <= 100.0, "Mean latency for \(size)B payload should be <= 100ms")
        }
    }
    
    @Test("Latency distribution over time")
    func testLatencyDistribution() async throws {
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        let testDurationSeconds = 10.0
        let startTime = CFAbsoluteTimeGetCurrent()
        var latencies: [Double] = []
        var buckets: [Int: [Double]] = [:] // Second -> latencies
        
        while CFAbsoluteTimeGetCurrent() - startTime < testDurationSeconds {
            let opStartTime = CFAbsoluteTimeGetCurrent()
            try await clientRef.ping()
            let latencyMS = (CFAbsoluteTimeGetCurrent() - opStartTime) * 1000
            
            let elapsedSeconds = Int(CFAbsoluteTimeGetCurrent() - startTime)
            buckets[elapsedSeconds, default: []].append(latencyMS)
            latencies.append(latencyMS)
            
            // Small delay between operations
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        let overallStats = LatencyStats(latencies: latencies)
        print("Overall latency distribution: \(overallStats.summary())")
        
        // Check consistency over time
        for (second, bucketLatencies) in buckets.sorted(by: { $0.key < $1.key }) {
            let bucketStats = LatencyStats(latencies: bucketLatencies)
            print("Second \(second): mean=\(String(format: "%.2f", bucketStats.mean))ms, " +
                  "p99=\(String(format: "%.2f", bucketStats.p99))ms")
            
            // Latency should remain consistent
            #expect(bucketStats.mean <= 50.0, "Latency should remain consistent over time")
        }
        
        #expect(overallStats.mean <= 30.0)
        #expect(overallStats.p99 <= 100.0)
    }
    
    @Test("Cold start latency")
    func testColdStartLatency() async throws {
        // Test first call latency (cold start)
        let (clientSystem, serverSystem) = await createConnectedSystems()
        
        // Create server actor
        let serverActor = LatencyTestActor(actorSystem: serverSystem)
        
        // Wait for actor registration
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Get client reference
        let clientRef = try $LatencyTestService.resolve(id: serverActor.id, using: clientSystem)
        
        // Measure cold start
        let coldStartTime = CFAbsoluteTimeGetCurrent()
        try await clientRef.ping()
        let coldStartLatencyMS = (CFAbsoluteTimeGetCurrent() - coldStartTime) * 1000
        
        // Measure warm calls
        var warmLatencies: [Double] = []
        for _ in 0..<10 {
            let startTime = CFAbsoluteTimeGetCurrent()
            try await clientRef.ping()
            let latencyMS = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            warmLatencies.append(latencyMS)
        }
        
        let warmStats = LatencyStats(latencies: warmLatencies)
        
        print("Cold start latency: \(String(format: "%.2f", coldStartLatencyMS))ms")
        print("Warm call latency: mean=\(String(format: "%.2f", warmStats.mean))ms")
        
        // Cold start should be within reasonable bounds
        #expect(coldStartLatencyMS <= 100.0, "Cold start should be <= 100ms")
        #expect(warmStats.mean <= 20.0, "Warm calls should be <= 20ms")
        
        // Cold start should be higher than warm calls
        #expect(coldStartLatencyMS > warmStats.mean,
                "Cold start should have higher latency than warm calls")
    }
    
    // MARK: - Helper Functions
    
    /// Create connected client and server systems
    private func createConnectedSystems() async -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let clientSystem = ActorEdgeSystem(transport: clientTransport)
        let serverSystem = ActorEdgeSystem()
        
        // Set up server transport handler
        Task {
            let stream = serverTransport.receive()
            for await envelope in stream {
                await handleServerEnvelope(envelope, serverSystem: serverSystem, transport: serverTransport)
            }
        }
        
        // Give the server handler task time to start
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        return (clientSystem, serverSystem)
    }
    
    /// Handle server-side envelope processing
    private func handleServerEnvelope(_ envelope: Envelope, serverSystem: ActorEdgeSystem, transport: MessageTransport) async {
        do {
            // Process the invocation
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            var decoder = try processor.createInvocationDecoder(from: envelope, system: serverSystem)
            
            // Find the target actor
            guard let actor = await serverSystem.registry?.find(id: envelope.recipient) else {
                throw ActorEdgeError.actorNotFound(envelope.recipient)
            }
            
            // Create response handler
            let resultHandler = LatencyResultHandler(transport: transport, requestEnvelope: envelope)
            
            // Dispatch to actor methods
            if let testActor = actor as? LatencyTestActor {
                if envelope.metadata.target.contains("ping") {
                    try await testActor.ping()
                    try await resultHandler.onReturnVoid()
                } else if envelope.metadata.target.contains("echo") {
                    let value: Int = try decoder.decodeNextArgument()
                    let result = try await testActor.echo(value)
                    try await resultHandler.onReturn(value: result)
                } else if envelope.metadata.target.contains("processWithDelay") {
                    let data: Data = try decoder.decodeNextArgument()
                    let delayMS: Int = try decoder.decodeNextArgument()
                    let result = try await testActor.processWithDelay(data, delayMS: delayMS)
                    try await resultHandler.onReturn(value: result)
                } else if envelope.metadata.target.contains("complexOperation") {
                    let input: ComplexInput = try decoder.decodeNextArgument()
                    let result = try await testActor.complexOperation(input)
                    try await resultHandler.onReturn(value: result)
                } else {
                    throw ActorEdgeError.invocationError("Unknown method: \(envelope.metadata.target)")
                }
            }
        } catch {
            // Send error response
            let processor = DistributedInvocationProcessor(serialization: serverSystem.serialization)
            let errorEnvelope = try! processor.createErrorEnvelope(
                to: envelope.sender ?? envelope.recipient,
                correlationID: envelope.metadata.callID,
                error: error,
                sender: envelope.recipient
            )
            _ = try? await transport.send(errorEnvelope)
        }
    }
}

// MARK: - Result Handler

/// Result handler for latency tests
final class LatencyResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable & Sendable
    
    private let transport: MessageTransport
    private let requestEnvelope: Envelope
    private let serialization: SerializationSystem
    
    init(transport: MessageTransport, requestEnvelope: Envelope) {
        self.transport = transport
        self.requestEnvelope = requestEnvelope
        self.serialization = SerializationSystem()
    }
    
    public func onReturn<Success: SerializationRequirement>(value: Success) async throws {
        let serializedValue = try serialization.serialize(value)
        let result = InvocationResult.success(serializedValue)
        let resultData = try serialization.serialize(result)
        
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(response)
    }
    
    public func onReturnVoid() async throws {
        let result = InvocationResult.void
        let resultData = try serialization.serialize(result)
        
        let response = Envelope.response(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(response)
    }
    
    public func onThrow<Err: Error>(error: Err) async throws {
        let serializedError = SerializedError(
            type: String(reflecting: type(of: error)),
            message: String(describing: error),
            serializedError: nil
        )
        
        let result = InvocationResult.error(serializedError)
        let resultData = try serialization.serialize(result)
        
        let errorEnvelope = Envelope.error(
            to: requestEnvelope.sender ?? requestEnvelope.recipient,
            callID: requestEnvelope.metadata.callID,
            manifest: resultData.manifest,
            payload: resultData.data
        )
        _ = try await transport.send(errorEnvelope)
    }
}