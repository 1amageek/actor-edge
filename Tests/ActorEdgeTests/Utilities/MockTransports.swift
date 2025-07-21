import Testing
import Foundation
@testable import ActorEdgeCore

/// Simplified and robust mock transport for testing
public final class MockMessageTransport: MessageTransport, @unchecked Sendable {
    // Thread-safe state management
    private let lock = NSLock()
    private var _sentEnvelopes: [Envelope] = []
    private var _mockResponse: Envelope?
    private var _shouldThrowError = false
    private var _errorToThrow: Error = TransportError.sendFailed(reason: "Mock error")
    private var _connected = true
    private var _callCount = 0
    private var _voidCallCount = 0
    private var _messageHandler: ((Envelope) async -> Envelope?)?
    
    public init() {}
    
    // MARK: - Configuration
    
    public var mockResponse: Envelope? {
        get { lock.withLock { _mockResponse } }
        set { lock.withLock { _mockResponse = newValue } }
    }
    
    public var shouldThrowError: Bool {
        get { lock.withLock { _shouldThrowError } }
        set { lock.withLock { _shouldThrowError = newValue } }
    }
    
    public var errorToThrow: Error {
        get { lock.withLock { _errorToThrow } }
        set { lock.withLock { _errorToThrow = newValue } }
    }
    
    // MARK: - State Access
    
    public var sentEnvelopes: [Envelope] {
        lock.withLock { _sentEnvelopes }
    }
    
    public var lastEnvelope: Envelope? {
        lock.withLock { _sentEnvelopes.last }
    }
    
    public var callCount: Int {
        lock.withLock { _callCount }
    }
    
    public var voidCallCount: Int {
        lock.withLock { _voidCallCount }
    }
    
    // MARK: - MessageTransport Implementation
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        try lock.withLock {
            if _shouldThrowError {
                throw _errorToThrow
            }
            
            if !_connected {
                throw TransportError.disconnected
            }
            
            _sentEnvelopes.append(envelope)
            _callCount += 1
            
            // Count void calls
            if envelope.messageType == .invocation && _mockResponse == nil {
                _voidCallCount += 1
            }
        }
        
        // Handle with message handler if set
        if let handler = lock.withLock({ _messageHandler }) {
            return await handler(envelope)
        }
        
        // Return configured mock response
        if let response = lock.withLock({ _mockResponse }) {
            var modifiedResponse = response
            // Update response to match request
            modifiedResponse = Envelope(
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
            return modifiedResponse
        }
        
        // Default echo response
        return Envelope.response(
            to: envelope.sender ?? envelope.recipient,
            callID: envelope.metadata.callID,
            manifest: envelope.manifest,
            payload: envelope.payload
        )
    }
    
    public func receive() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            if !lock.withLock({ _connected }) {
                continuation.finish()
            }
            // For mock, we don't emit any received envelopes by default
            continuation.finish()
        }
    }
    
    public func close() async throws {
        lock.withLock { _connected = false }
    }
    
    public var isConnected: Bool {
        lock.withLock { _connected }
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "mock",
            attributes: ["version": "1.0", "test": "true"],
            endpoint: "mock://test",
            isSecure: false
        )
    }
    
    // MARK: - Message Handler
    
    public func setMessageHandler(_ handler: @escaping (Envelope) async -> Envelope?) {
        lock.withLock { _messageHandler = handler }
    }
    
    // MARK: - Test Helpers
    
    public func enqueueReceiveEnvelope(_ envelope: Envelope) {
        // This mock doesn't actually queue receive envelopes
        // It's a send-only mock primarily
    }
    
    public func reset() {
        lock.withLock {
            _sentEnvelopes.removeAll()
            _mockResponse = nil
            _shouldThrowError = false
            _errorToThrow = TransportError.sendFailed(reason: "Mock error")
            _connected = true
            _callCount = 0
            _voidCallCount = 0
            _messageHandler = nil
        }
    }
    
    public func disconnect() {
        lock.withLock { _connected = false }
    }
    
    public func reconnect() {
        lock.withLock { _connected = true }
    }
    
    public func setMockResponseForNextCall(_ envelope: Envelope) {
        lock.withLock { _mockResponse = envelope }
    }
    
    public func getLastContextHeaders() -> [String: String] {
        lock.withLock { _sentEnvelopes.last?.metadata.headers ?? [:] }
    }
}

// MARK: - NSLock Extension

extension NSLock {
    func withLock<T>(_ work: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        return try work()
    }
}

// MARK: - Enhanced Bidirectional Transport

/// Enhanced transport for bi-directional testing
public final class BidirectionalMockTransport: MessageTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _pairedTransport: BidirectionalMockTransport?
    private var _messageHandler: ((Envelope) async -> Envelope?)?
    private var _receivedEnvelopes: [Envelope] = []
    private var _sentEnvelopes: [Envelope] = []
    private var _connected = true
    private let receiveStream = AsyncStream<Envelope>.makeStream()
    
    public init() {}
    
    public func pair(with other: BidirectionalMockTransport) {
        lock.withLock {
            _pairedTransport = other
        }
        other.lock.withLock {
            other._pairedTransport = self
        }
    }
    
    public func setMessageHandler(_ handler: @escaping (Envelope) async -> Envelope?) {
        lock.withLock { _messageHandler = handler }
    }
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        try lock.withLock {
            if !_connected {
                throw TransportError.disconnected
            }
            
            _sentEnvelopes.append(envelope)
        }
        
        // If paired, send to the other transport
        if let paired = lock.withLock({ _pairedTransport }) {
            Task {
                await paired.handleReceivedEnvelope(envelope)
            }
        }
        
        // Handle locally if we have a message handler
        if let handler = lock.withLock({ _messageHandler }) {
            return await handler(envelope)
        }
        
        return nil
    }
    
    private func handleReceivedEnvelope(_ envelope: Envelope) async {
        lock.withLock { 
            _receivedEnvelopes.append(envelope)
        }
        
        // Yield to receive stream
        receiveStream.continuation.yield(envelope)
        
        // Process with handler if available
        if let handler = lock.withLock({ _messageHandler }) {
            if let response = await handler(envelope) {
                // Send response back to paired transport
                if let paired = lock.withLock({ _pairedTransport }) {
                    _ = try? await paired.send(response)
                }
            }
        }
    }
    
    public func receive() -> AsyncStream<Envelope> {
        receiveStream.stream
    }
    
    public func close() async throws {
        lock.withLock { 
            _connected = false
        }
        receiveStream.continuation.finish()
    }
    
    public var isConnected: Bool {
        lock.withLock { _connected }
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "bidirectional-mock",
            attributes: ["paired": lock.withLock { _pairedTransport != nil ? "true" : "false" }],
            endpoint: "bidirectional-mock://test",
            isSecure: true
        )
    }
    
    // Test helpers
    public var sentEnvelopes: [Envelope] {
        lock.withLock { _sentEnvelopes }
    }
    
    public var receivedEnvelopes: [Envelope] {
        lock.withLock { _receivedEnvelopes }
    }
    
    public func clearEnvelopes() {
        lock.withLock {
            _sentEnvelopes.removeAll()
            _receivedEnvelopes.removeAll()
        }
    }
}

// MARK: - Mock Transport Factory

public enum MockTransportFactory {
    
    /// Create a successful transport with predefined response
    public static func successful<T: Codable>(response: T) -> MockMessageTransport {
        let transport = MockMessageTransport()
        let responseData = try! JSONEncoder().encode(response)
        transport.mockResponse = Envelope.response(
            to: ActorEdgeID(),
            callID: UUID().uuidString,
            manifest: SerializationManifest.json(),
            payload: responseData
        )
        return transport
    }
    
    /// Create a failing transport
    public static func failing(error: Error = TransportError.sendFailed(reason: "Mock failure")) -> MockMessageTransport {
        let transport = MockMessageTransport()
        transport.shouldThrowError = true
        transport.errorToThrow = error
        return transport
    }
    
    /// Create a disconnected transport
    public static func disconnected() -> MockMessageTransport {
        let transport = MockMessageTransport()
        transport.disconnect()
        return transport
    }
    
    /// Create a transport with custom handler
    public static func withHandler(_ handler: @escaping (Envelope) async -> Envelope?) -> MockMessageTransport {
        let transport = MockMessageTransport()
        transport.setMessageHandler(handler)
        return transport
    }
    
    /// Create a paired transport set for bidirectional communication
    public static func createConnectedPair() -> (client: BidirectionalMockTransport, server: BidirectionalMockTransport) {
        let client = BidirectionalMockTransport()
        let server = BidirectionalMockTransport()
        client.pair(with: server)
        return (client, server)
    }
}