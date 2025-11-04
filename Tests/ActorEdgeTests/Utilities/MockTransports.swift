import Testing
import Foundation
import ActorRuntime
@testable import ActorEdgeCore

/// Simplified and robust mock transport for testing
public final class MockDistributedTransport: DistributedTransport, @unchecked Sendable {
    // Thread-safe state management
    private let lock = NSLock()
    private var _sentInvocations: [InvocationEnvelope] = []
    private var _mockResponse: ResponseEnvelope?
    private var _shouldThrowError = false
    private var _errorToThrow: Error = RuntimeError.transportFailed("Mock error")
    private var _connected = true
    private var _callCount = 0

    public init() {}

    // MARK: - Configuration

    public var mockResponse: ResponseEnvelope? {
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

    public var sentInvocations: [InvocationEnvelope] {
        lock.withLock { _sentInvocations }
    }

    public var lastInvocation: InvocationEnvelope? {
        lock.withLock { _sentInvocations.last }
    }

    public var callCount: Int {
        lock.withLock { _callCount }
    }

    public var isConnected: Bool {
        lock.withLock { _connected }
    }

    // MARK: - DistributedTransport Implementation

    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        try lock.withLock {
            if _shouldThrowError {
                throw _errorToThrow
            }

            if !_connected {
                throw RuntimeError.transportFailed("Transport disconnected")
            }

            _sentInvocations.append(envelope)
            _callCount += 1
        }

        // Return configured mock response or create a default success response
        if let response = lock.withLock({ _mockResponse }) {
            return response
        }

        // Default success response
        return ResponseEnvelope(
            callID: envelope.callID,
            result: .success(Data())
        )
    }

    public func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Mock transport doesn't need to implement server-side response sending
    }

    public var incomingInvocations: AsyncStream<InvocationEnvelope> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func close() async throws {
        lock.withLock { _connected = false }
    }

    // MARK: - Test Helpers

    public func reset() {
        lock.withLock {
            _sentInvocations.removeAll()
            _mockResponse = nil
            _shouldThrowError = false
            _errorToThrow = RuntimeError.transportFailed("Mock error")
            _connected = true
            _callCount = 0
        }
    }

    public func disconnect() {
        lock.withLock { _connected = false }
    }

    public func reconnect() {
        lock.withLock { _connected = true }
    }

    public func setMockResponseForNextCall(_ envelope: ResponseEnvelope) {
        lock.withLock { _mockResponse = envelope }
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

// MARK: - Mock Transport Factory

public enum MockTransportFactory {

    /// Create a successful transport with predefined response
    public static func successful<T: Codable>(response: T, callID: String = UUID().uuidString) -> MockDistributedTransport {
        let transport = MockDistributedTransport()
        let responseData = try! JSONEncoder().encode(response)
        transport.mockResponse = ResponseEnvelope(
            callID: callID,
            result: .success(responseData)
        )
        return transport
    }

    /// Create a failing transport
    public static func failing(error: RuntimeError = .transportFailed("Mock failure")) -> MockDistributedTransport {
        let transport = MockDistributedTransport()
        transport.shouldThrowError = true
        transport.errorToThrow = error
        return transport
    }

    /// Create a disconnected transport
    public static func disconnected() -> MockDistributedTransport {
        let transport = MockDistributedTransport()
        transport.disconnect()
        return transport
    }
}
