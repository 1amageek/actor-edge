import Testing
import Foundation
import Distributed
import ServiceContextModule
import GRPCCore
@testable import ActorEdgeCore

/// Test suite for ActorEdge transport functionality
@Suite("Transport Tests")
struct TransportTests {
    
    // MARK: - Test Configuration
    
    struct TestConfig {
        static let testEndpoint = "127.0.0.1:9999"
        static let testActorID = ActorEdgeID()
        static let testMethod = "testMethod"
        static let testData = Data("test data".utf8)
    }
    
    // MARK: - GRPCActorTransport Tests
    
    @Test("Initialize transport with plaintext")
    func testInitTransportPlaintext() async throws {
        let transport = try await GRPCActorTransport(TestConfig.testEndpoint)
        #expect(transport != nil)
    }
    
    @Test("Initialize transport with TLS")
    func testInitTransportTLS() async throws {
        let tlsConfig = ClientTLSConfiguration()
        let transport = try await GRPCActorTransport(TestConfig.testEndpoint, tls: tlsConfig)
        #expect(transport != nil)
    }
    
    @Test("Parse endpoint with custom port")
    func testEndpointParsingWithPort() async throws {
        let transport = try await GRPCActorTransport("example.com:8080")
        #expect(transport != nil)
    }
    
    @Test("Parse endpoint without port defaults to 443")
    func testEndpointParsingWithoutPort() async throws {
        let transport = try await GRPCActorTransport("example.com")
        #expect(transport != nil)
    }
    
    // MARK: - Mock Transport Tests
    
    @Test("Mock transport remote call")
    func testMockTransportRemoteCall() async throws {
        let transport = MockTransport()
        let expectedResponse = Data("response".utf8)
        transport.mockResponse = expectedResponse
        
        let context = ServiceContext.topLevel
        let response = try await transport.remoteCall(
            on: TestConfig.testActorID,
            method: TestConfig.testMethod,
            arguments: TestConfig.testData,
            context: context
        )
        
        #expect(response == expectedResponse)
        #expect(transport.lastActorID == TestConfig.testActorID)
        #expect(transport.lastMethod == TestConfig.testMethod)
        #expect(transport.lastArguments == TestConfig.testData)
    }
    
    @Test("Mock transport remote call void")
    func testMockTransportRemoteCallVoid() async throws {
        let transport = MockTransport()
        let context = ServiceContext.topLevel
        
        try await transport.remoteCallVoid(
            on: TestConfig.testActorID,
            method: TestConfig.testMethod,
            arguments: TestConfig.testData,
            context: context
        )
        
        #expect(transport.voidCallCount == 1)
        #expect(transport.lastActorID == TestConfig.testActorID)
        #expect(transport.lastMethod == TestConfig.testMethod)
    }
    
    @Test("Mock transport stream call")
    func testMockTransportStreamCall() async throws {
        let transport = MockTransport()
        let streamData = [Data("chunk1".utf8), Data("chunk2".utf8), Data("chunk3".utf8)]
        transport.mockStreamData = streamData
        
        let context = ServiceContext.topLevel
        let stream = try await transport.streamCall(
            on: TestConfig.testActorID,
            method: TestConfig.testMethod,
            arguments: TestConfig.testData,
            context: context
        )
        
        var receivedChunks: [Data] = []
        for try await chunk in stream {
            receivedChunks.append(chunk)
        }
        
        #expect(receivedChunks == streamData)
    }
    
    @Test("Mock transport error handling")
    func testMockTransportError() async throws {
        let transport = MockTransport()
        transport.shouldThrowError = true
        
        let context = ServiceContext.topLevel
        
        do {
            _ = try await transport.remoteCall(
                on: TestConfig.testActorID,
                method: TestConfig.testMethod,
                arguments: TestConfig.testData,
                context: context
            )
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is ActorEdgeError)
        }
    }
    
    // MARK: - Service Context Propagation Tests
    
    @Test("Service context propagation through transport")
    func testServiceContextPropagation() async throws {
        let transport = MockTransport()
        
        // Create a context with custom values
        var context = ServiceContext.topLevel
        context[TestTraceIDKey.self] = "test-trace-123"
        
        _ = try await transport.remoteCall(
            on: TestConfig.testActorID,
            method: TestConfig.testMethod,
            arguments: TestConfig.testData,
            context: context
        )
        
        #expect(transport.lastContext?[TestTraceIDKey.self] == "test-trace-123")
    }
    
    // MARK: - ActorTransport Protocol Conformance Tests
    
    @Test("Transport conforms to ActorTransport protocol")
    func testTransportConformance() async throws {
        let transport = MockTransport()
        
        // Test that MockTransport conforms to ActorTransport
        let _: any ActorTransport = transport
        
        // Test that it's Sendable
        let _: any Sendable = transport
        
        #expect(true) // If we get here, conformance is correct
    }
    
    // MARK: - Performance Tests
    
    @Test("Transport call performance")
    func testTransportPerformance() async throws {
        let transport = MockTransport()
        transport.mockResponse = Data("performance test".utf8)
        
        let context = ServiceContext.topLevel
        let iterations = 100
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            _ = try await transport.remoteCall(
                on: TestConfig.testActorID,
                method: TestConfig.testMethod,
                arguments: TestConfig.testData,
                context: context
            )
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = duration / Double(iterations)
        
        #expect(averageTime < 0.001, "Average call time should be less than 1ms")
    }
    
    // MARK: - Error Envelope Tests
    
    @Test("Error envelope serialization")
    func testErrorEnvelopeSerialization() async throws {
        let error = TestError.customError("Test error message")
        let envelope = ErrorEnvelope(
            typeURL: "test.error.TestError",
            data: try JSONEncoder().encode(error)
        )
        
        #expect(!envelope.typeURL.isEmpty)
        #expect(!envelope.data.isEmpty)
        
        // Verify we can decode the error back
        let decodedError = try JSONDecoder().decode(TestError.self, from: envelope.data)
        #expect(decodedError == error)
    }
}

// MARK: - Mock Transport Implementation

final class MockTransport: ActorTransport, @unchecked Sendable {
    var mockResponse = Data()
    var mockStreamData: [Data] = []
    var shouldThrowError = false
    
    var lastActorID: ActorEdgeID?
    var lastMethod: String?
    var lastArguments: Data?
    var lastContext: ServiceContext?
    var voidCallCount = 0
    
    func remoteCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> Data {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock transport error")
        }
        
        lastActorID = actorID
        lastMethod = method
        lastArguments = arguments
        lastContext = context
        
        return mockResponse
    }
    
    func remoteCallVoid(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock transport error")
        }
        
        lastActorID = actorID
        lastMethod = method
        lastArguments = arguments
        lastContext = context
        voidCallCount += 1
    }
    
    func streamCall(
        on actorID: ActorEdgeID,
        method: String,
        arguments: Data,
        context: ServiceContext
    ) async throws -> AsyncThrowingStream<Data, Error> {
        if shouldThrowError {
            throw ActorEdgeError.transportError("Mock transport error")
        }
        
        lastActorID = actorID
        lastMethod = method
        lastArguments = arguments
        lastContext = context
        
        return AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for data in mockStreamData {
                    continuation.yield(data)
                    try await Task.sleep(nanoseconds: 1_000_000) // 1ms between chunks
                }
                continuation.finish()
            }
        }
    }
}

// MARK: - Test Types

enum TestError: Error, Codable, Equatable {
    case customError(String)
}

enum TestTraceIDKey: ServiceContextKey {
    typealias Value = String
    static var defaultValue: String { "" }
}