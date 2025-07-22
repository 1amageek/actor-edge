//===----------------------------------------------------------------------===//
//
// This source file is part of the ActorEdge open source project
//
// Copyright (c) 2024 ActorEdge contributors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation

/// In-memory implementation of MessageTransport for testing.
///
/// This transport maintains an internal queue of messages and can be paired
/// with another InMemoryMessageTransport to simulate bidirectional communication
/// without actual network operations.
public final class InMemoryMessageTransport: MessageTransport, @unchecked Sendable {
    private let queue = MessageQueue()
    private var pairedTransport: InMemoryMessageTransport?
    private var messageHandler: ((Envelope) async throws -> Envelope?)?
    private var connected = true
    private let transportID = UUID().uuidString
    
    /// Creates a new in-memory transport.
    public init() {}
    
    /// Pairs this transport with another for bidirectional communication.
    public func pair(with other: InMemoryMessageTransport) {
        self.pairedTransport = other
        other.pairedTransport = self
    }
    
    /// Sets a custom message handler for processing incoming messages.
    /// This is useful for simulating server-side behavior in tests.
    public func setMessageHandler(
        _ handler: @escaping (Envelope) async throws -> Envelope?
    ) {
        self.messageHandler = handler
    }
    
    // MARK: - MessageTransport
    
    public func send(_ envelope: Envelope) async throws -> Envelope? {
        guard connected else {
            throw TransportError.disconnected
        }
        
        // If we have a message handler, use it (simulates server processing)
        if let handler = messageHandler {
            return try await handler(envelope)
        }
        
        // If paired, deliver to the appropriate queue
        if let paired = pairedTransport {
            // Simulate network delay if needed
            await simulateNetworkDelay()
            
            // For responses and errors, deliver back to the paired transport's queue
            // so the original sender can retrieve it
            if envelope.messageType == .response || envelope.messageType == .error {
                // The paired transport sent an invocation, so it's waiting for this response
                await paired.queue.enqueue(envelope)
            } else {
                // For invocations and other messages, deliver to paired transport
                await paired.queue.enqueue(envelope)
                
                // For request-response patterns, wait for a response
                if envelope.messageType == .invocation {
                    // Wait for response with matching call ID
                    let response = await waitForResponse(callID: envelope.metadata.callID)
                    return response
                }
            }
        }
        
        return nil
    }
    
    public func receive() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            Task {
                while connected {
                    if let envelope = await queue.dequeue() {
                        continuation.yield(envelope)
                    } else {
                        // Queue is closed
                        break
                    }
                }
                continuation.finish()
            }
        }
    }
    
    public func close() async throws {
        connected = false
        await queue.close()
        
        // Unpair from the other transport
        if let paired = pairedTransport {
            paired.pairedTransport = nil
        }
        pairedTransport = nil
    }
    
    public var isConnected: Bool {
        connected
    }
    
    public var metadata: TransportMetadata {
        TransportMetadata(
            transportType: "in-memory",
            attributes: [
                "transportID": transportID,
                "paired": pairedTransport != nil ? "true" : "false"
            ],
            endpoint: "memory://\(transportID)",
            isSecure: true // In-memory is inherently secure
        )
    }
    
    // MARK: - Test Helpers
    
    /// Enqueues a message directly (for testing).
    public func enqueueMessage(_ envelope: Envelope) async {
        await queue.enqueue(envelope)
    }
    
    /// Gets all sent messages (for testing assertions).
    public func getSentMessages() async -> [Envelope] {
        await queue.getAllMessages()
    }
    
    /// Clears all messages (for test cleanup).
    public func clearMessages() async {
        await queue.clear()
    }
    
    // MARK: - Private Helpers
    
    private func simulateNetworkDelay() async {
        // Optionally simulate network latency for more realistic tests
        // For now, no delay
    }
    
    private func waitForResponse(callID: String) async -> Envelope? {
        // Use continuation-based approach for better performance
        return await queue.waitForResponse(callID: callID)
    }
}

/// Thread-safe message queue for the in-memory transport.
private actor MessageQueue {
    private var messages: [Envelope] = []
    private var waitingContinuations: [CheckedContinuation<Envelope?, Never>] = []
    private var responseWaiters: [String: CheckedContinuation<Envelope?, Never>] = [:]
    private var isClosed = false
    
    func enqueue(_ envelope: Envelope) {
        guard !isClosed else { return }
        
        // Check if this is a response that someone is waiting for
        let callID = envelope.metadata.callID
        if (envelope.messageType == .response || envelope.messageType == .error),
           let waiter = responseWaiters.removeValue(forKey: callID) {
            waiter.resume(returning: envelope)
            return
        }
        
        // If someone is waiting, deliver immediately
        if !waitingContinuations.isEmpty {
            let continuation = waitingContinuations.removeFirst()
            continuation.resume(returning: envelope)
        } else {
            // Otherwise, queue it
            messages.append(envelope)
        }
    }
    
    func dequeue() async -> Envelope? {
        // If we have messages, return one
        if !messages.isEmpty {
            return messages.removeFirst()
        }
        
        // If closed, return nil
        if isClosed {
            return nil
        }
        
        // Otherwise, wait for a message
        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }
    
    func findAndRemove(where predicate: (Envelope) -> Bool) -> Envelope? {
        guard let index = messages.firstIndex(where: predicate) else {
            return nil
        }
        return messages.remove(at: index)
    }
    
    func getAllMessages() -> [Envelope] {
        messages
    }
    
    func clear() {
        messages.removeAll()
    }
    
    func close() {
        isClosed = true
        // Resume all waiting continuations with nil
        for continuation in waitingContinuations {
            continuation.resume(returning: nil)
        }
        waitingContinuations.removeAll()
        
        // Resume all response waiters with nil
        for (_, waiter) in responseWaiters {
            waiter.resume(returning: nil)
        }
        responseWaiters.removeAll()
    }
    
    func waitForResponse(callID: String) async -> Envelope? {
        // Check if response is already in the queue
        if let index = messages.firstIndex(where: { envelope in
            envelope.metadata.callID == callID &&
            (envelope.messageType == .response || envelope.messageType == .error)
        }) {
            return messages.remove(at: index)
        }
        
        // If closed, return nil
        if isClosed {
            return nil
        }
        
        // Wait for response
        return await withCheckedContinuation { continuation in
            responseWaiters[callID] = continuation
        }
    }
}

// MARK: - Test Factory

public extension InMemoryMessageTransport {
    /// Creates a pair of connected transports for testing.
    static func createConnectedPair() -> (client: InMemoryMessageTransport, server: InMemoryMessageTransport) {
        let client = InMemoryMessageTransport()
        let server = InMemoryMessageTransport()
        client.pair(with: server)
        return (client, server)
    }
}