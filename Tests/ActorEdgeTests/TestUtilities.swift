import Foundation
import Distributed
import ServiceContextModule
@testable import ActorEdgeCore

// MARK: - Shared Mock Message Transport

/// A shared mock implementation of MessageTransport for testing
public final class MockMessageTransport: MessageTransport, @unchecked Sendable {
    // State tracking
    public private(set) var sentEnvelopes: [Envelope] = []
    public private(set) var lastEnvelope: Envelope?
    public private(set) var voidCallCount = 0
    
    // Configuration
    public var mockResponse: Envelope?
    public var shouldThrowError = false
    public var shouldReturnMockResponse = false
    public var errorToThrow: Error = TransportError.sendFailed(reason: "Mock error")
    
    // Connection state
    private var connected = true
    private var receivedEnvelopes: [Envelope] = []
    
    public init() {}
    
    // MARK: - MessageTransport Implementation
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        if shouldThrowError {
            throw errorToThrow
        }
        
        if !connected {
            throw TransportError.disconnected
        }
        
        // Record the sent envelope
        sentEnvelopes.append(envelope)
        lastEnvelope = envelope
        
        // Count void calls
        if envelope.messageType == .invocation && mockResponse == nil && !shouldReturnMockResponse {
            voidCallCount += 1
        }
        
        // Return mock response if configured
        if shouldReturnMockResponse || mockResponse != nil {
            if var response = mockResponse {
                // Update response to match request metadata
                response = Envelope(
                    recipient: envelope.sender ?? envelope.recipient,
                    sender: envelope.recipient,
                    manifest: response.manifest,
                    payload: response.payload,
                    metadata: MessageMetadata(
                        callID: envelope.metadata.callID,
                        target: response.metadata.target,
                        headers: response.metadata.headers
                    ),
                    messageType: response.messageType
                )
                return response
            } else {
                // Generate default response
                return Envelope.response(
                    to: envelope.sender ?? envelope.recipient,
                    callID: envelope.metadata.callID,
                    manifest: SerializationManifest(serializerID: "json"),
                    payload: Data("mock response".utf8)
                )
            }
        }
        
        return nil
    }
    
    public func receive() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            for envelope in receivedEnvelopes {
                continuation.yield(envelope)
            }
            receivedEnvelopes.removeAll()
            
            if !connected {
                continuation.finish()
            }
        }
    }
    
    public func close() async throws {
        connected = false
        receivedEnvelopes.removeAll()
    }
    
    public var isConnected: Bool {
        connected
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "mock",
            attributes: ["test": "true", "mock-id": UUID().uuidString],
            endpoint: "mock://test",
            isSecure: false
        )
    }
    
    // MARK: - Test Helper Methods
    
    /// Enqueue an envelope to be received
    public func enqueueReceivedEnvelope(_ envelope: Envelope) {
        receivedEnvelopes.append(envelope)
    }
    
    /// Simulate disconnection
    public func disconnect() {
        connected = false
    }
    
    /// Reconnect after disconnection
    public func reconnect() {
        connected = true
    }
    
    /// Reset all state
    public func reset() {
        sentEnvelopes.removeAll()
        receivedEnvelopes.removeAll()
        lastEnvelope = nil
        voidCallCount = 0
        mockResponse = nil
        shouldThrowError = false
        shouldReturnMockResponse = false
        errorToThrow = TransportError.sendFailed(reason: "Mock error")
        connected = true
    }
    
    /// Get context headers from last sent envelope
    public func getLastContextHeaders() -> [String: String]? {
        return lastEnvelope?.metadata.headers
    }
}

// MARK: - Test Envelope Factory

/// Factory for creating test envelopes with common configurations
public enum TestEnvelopeFactory {
    
    /// Create a basic invocation envelope
    public static func invocation(
        to recipient: ActorEdgeID = ActorEdgeID(),
        from sender: ActorEdgeID? = ActorEdgeID(),
        target: String = "testMethod",
        callID: String = UUID().uuidString,
        payload: Data = Data("test payload".utf8),
        headers: [String: String] = [:]
    ) -> Envelope {
        return Envelope.invocation(
            to: recipient,
            from: sender,
            target: target,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: payload,
            headers: headers
        )
    }
    
    /// Create a response envelope
    public static func response(
        to recipient: ActorEdgeID = ActorEdgeID(),
        from sender: ActorEdgeID? = ActorEdgeID(),
        callID: String = UUID().uuidString,
        payload: Data = Data("response data".utf8),
        headers: [String: String] = [:]
    ) -> Envelope {
        return Envelope.response(
            to: recipient,
            from: sender,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: payload,
            headers: headers
        )
    }
    
    /// Create an error envelope
    public static func error(
        to recipient: ActorEdgeID = ActorEdgeID(),
        from sender: ActorEdgeID? = ActorEdgeID(),
        callID: String = UUID().uuidString,
        error: Error,
        headers: [String: String] = [:]
    ) -> Envelope {
        let errorData = try! JSONEncoder().encode(error.localizedDescription)
        
        return Envelope.error(
            to: recipient,
            from: sender,
            callID: callID,
            manifest: SerializationManifest(serializerID: "json"),
            payload: errorData,
            headers: headers
        )
    }
    
    /// Create an envelope with custom metadata
    public static func custom(
        messageType: MessageType,
        recipient: ActorEdgeID = ActorEdgeID(),
        sender: ActorEdgeID? = ActorEdgeID(),
        target: String = "",
        callID: String = UUID().uuidString,
        manifest: SerializationManifest = SerializationManifest(serializerID: "json"),
        payload: Data = Data(),
        headers: [String: String] = [:]
    ) -> Envelope {
        return Envelope(
            recipient: recipient,
            sender: sender,
            manifest: manifest,
            payload: payload,
            metadata: MessageMetadata(
                callID: callID,
                target: target,
                headers: headers
            ),
            messageType: messageType
        )
    }
    
    /// Create a batch of test envelopes
    public static func batch(
        count: Int,
        targetPrefix: String = "method",
        payloadPrefix: String = "data"
    ) -> [Envelope] {
        return (0..<count).map { i in
            invocation(
                target: "\(targetPrefix)-\(i)",
                payload: Data("\(payloadPrefix)-\(i)".utf8)
            )
        }
    }
}

// MARK: - Test Service Context Keys

/// Test context key for tracing
public enum TestTraceIDKey: ServiceContextKey {
    public typealias Value = String
    public static var defaultValue: String { "" }
}

/// Test context key for user information
public enum TestUserIDKey: ServiceContextKey {
    public typealias Value = String
    public static var defaultValue: String { "" }
}

/// Test context key for correlation
public enum TestCorrelationIDKey: ServiceContextKey {
    public typealias Value = String
    public static var defaultValue: String { "" }
}

// MARK: - Test Actor Types

/// Simple test actor protocol
public protocol TestActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func echo(_ message: String) async throws -> String
    distributed func getCount() async throws -> Int
    distributed func increment() async throws
}

/// Simple test actor implementation
public distributed actor SimpleTestActor: TestActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    private var count = 0
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func echo(_ message: String) async throws -> String {
        return "Echo: \(message)"
    }
    
    public distributed func getCount() async throws -> Int {
        return count
    }
    
    public distributed func increment() async throws {
        count += 1
    }
}

// MARK: - Test Error Types

/// Common test errors
public enum TestError: Error, Codable, Equatable {
    case simpleError
    case errorWithMessage(String)
    case errorWithCode(Int)
}

// MARK: - Test Message Types

/// Simple test message
public struct TestMessage: Codable, Sendable, Equatable {
    public let id: Int
    public let content: String
    public let timestamp: Date
    
    public init(id: Int, content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
}

/// Complex test message with nested types
public struct ComplexTestMessage: Codable, Sendable, Equatable {
    public let id: UUID
    public let messages: [TestMessage]
    public let metadata: [String: String]
    public let optional: String?
    
    public init(
        id: UUID = UUID(),
        messages: [TestMessage] = [],
        metadata: [String: String] = [:],
        optional: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.metadata = metadata
        self.optional = optional
    }
}

// MARK: - Test Assertions

/// Common test assertions for envelopes
public enum EnvelopeAssertions {
    
    /// Assert that two envelopes are equivalent (ignoring timestamps)
    public static func assertEqual(
        _ actual: Envelope,
        _ expected: Envelope,
        file: StaticString = #file,
        line: UInt = #line
    ) -> Bool {
        guard actual.recipient == expected.recipient else {
            print("Recipients don't match at \(file):\(line)")
            return false
        }
        
        guard actual.sender == expected.sender else {
            print("Senders don't match at \(file):\(line)")
            return false
        }
        
        guard actual.metadata.callID == expected.metadata.callID else {
            print("Call IDs don't match at \(file):\(line)")
            return false
        }
        
        guard actual.metadata.target == expected.metadata.target else {
            print("Targets don't match at \(file):\(line)")
            return false
        }
        
        guard actual.messageType == expected.messageType else {
            print("Message types don't match at \(file):\(line)")
            return false
        }
        
        guard actual.payload == expected.payload else {
            print("Payloads don't match at \(file):\(line)")
            return false
        }
        
        return true
    }
}