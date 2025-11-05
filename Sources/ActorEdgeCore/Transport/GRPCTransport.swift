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

import ActorRuntime
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Synchronization
import Logging
import Metrics

/// gRPC implementation of ActorRuntime's DistributedTransport protocol
///
/// This transport uses JSON serialization to send ActorRuntime's InvocationEnvelope
/// and ResponseEnvelope directly over gRPC, without intermediate protobuf conversion.
public final class GRPCTransport: DistributedTransport, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let logger: Logger
    private let transportLatency: Timer
    private let incomingContinuation: AsyncStream<InvocationEnvelope>.Continuation
    private let connectionTask: Task<Void, Error>?

    /// Connection readiness state
    private let readyStateMachine: ReadyStateMachine

    public let incomingInvocations: AsyncStream<InvocationEnvelope>

    /// Thread-safe state machine for connection readiness
    private final class ReadyStateMachine: Sendable {
        private let state: Mutex<State>

        private enum State {
            case notReady
            case ready
            case failed(Error)
        }

        init() {
            self.state = Mutex(.notReady)
        }

        func markReady() {
            state.withLock { $0 = .ready }
        }

        func markFailed(_ error: Error) {
            state.withLock {
                if case .notReady = $0 {
                    $0 = .failed(error)
                }
            }
        }

        func checkReady() throws {
            try state.withLock {
                switch $0 {
                case .notReady:
                    throw GRPCTransportError.notReady
                case .ready:
                    return
                case .failed(let error):
                    throw GRPCTransportError.connectionFailed(error)
                }
            }
        }

        func isReady() -> Bool {
            state.withLock {
                if case .ready = $0 {
                    return true
                }
                return false
            }
        }
    }

    /// Errors specific to GRPCTransport
    public enum GRPCTransportError: Error, CustomStringConvertible {
        case notReady
        case connectionFailed(Error)
        case readinessTimeout

        public var description: String {
            switch self {
            case .notReady:
                return "gRPC transport is not ready yet"
            case .connectionFailed(let error):
                return "gRPC connection failed: \(error)"
            case .readinessTimeout:
                return "Timeout waiting for gRPC connection readiness"
            }
        }
    }

    /// Creates a GRPCTransport with automatic connection management.
    ///
    /// This initializer starts the gRPC client's connection management in the background.
    /// The transport will automatically manage the HTTP/2 connection lifecycle.
    ///
    /// - Parameters:
    ///   - client: The gRPC client instance
    ///   - logger: Logger for transport operations
    ///   - metricsNamespace: Namespace for metrics
    ///   - startConnections: Whether to start runConnections() automatically (default: true)
    public init(
        client: GRPCClient<HTTP2ClientTransport.Posix>,
        logger: Logger = Logger(label: "ActorEdge.GRPCTransport"),
        metricsNamespace: String = "actor_edge",
        startConnections: Bool = true
    ) {
        self.client = client
        self.logger = logger
        let metricNames = MetricNames(namespace: metricsNamespace)
        self.transportLatency = Timer(label: metricNames.messageTransportLatencySeconds)
        self.readyStateMachine = ReadyStateMachine()

        // Create incoming invocations stream (required by protocol but unused in client-only mode)
        var continuation: AsyncStream<InvocationEnvelope>.Continuation!
        let stream = AsyncStream<InvocationEnvelope> { cont in
            continuation = cont
        }
        self.incomingContinuation = continuation
        self.incomingInvocations = stream

        // Start connection management in background if requested
        if startConnections {
            let stateMachine = self.readyStateMachine
            self.connectionTask = Task {
                do {
                    try await client.runConnections()
                } catch is CancellationError {
                    // Normal cancellation during shutdown
                    logger.debug("Connection task cancelled")
                } catch {
                    // Mark as failed immediately so clients know about the error
                    stateMachine.markFailed(error)
                    logger.error("Connection task failed: \(error)")
                    throw error
                }
            }
        } else {
            self.connectionTask = nil
            // If not auto-starting, mark as ready immediately
            self.readyStateMachine.markReady()
        }
    }

    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        logger.trace("Sending invocation", metadata: ["callID": "\(envelope.callID)"])

        // Record start time for latency measurement
        let startTime = DispatchTime.now()

        // Create method descriptor
        let method = MethodDescriptor(
            service: ServiceDescriptor(fullyQualifiedService: "DistributedActor"),
            method: "RemoteCall"
        )

        // Make gRPC unary call with JSON serialization
        var callOptions = CallOptions.defaults
        callOptions.timeout = .seconds(30)

        let response: ResponseEnvelope
        do {
            response = try await client.unary(
                request: ClientRequest(message: envelope),
                descriptor: method,
                serializer: JSONSerializer<InvocationEnvelope>(),
                deserializer: JSONDeserializer<ResponseEnvelope>(),
                options: callOptions
            ) { response in
                return try response.message
            }

            // Mark as ready on first successful RPC
            readyStateMachine.markReady()
        } catch {
            // If this is the first call and it fails, mark as failed
            readyStateMachine.markFailed(error)
            throw error
        }

        // Record latency
        let endTime = DispatchTime.now()
        let latencyNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
        let latencySeconds = Double(latencyNanos) / 1_000_000_000.0
        transportLatency.recordSeconds(latencySeconds)

        logger.trace("Received response", metadata: ["callID": "\(response.callID)"])
        return response
    }

    /// Wait until the transport is ready or throws if connection failed.
    ///
    /// This method polls the connection state until it becomes ready or fails.
    /// Use this in `grpcClient()` factory to ensure the connection is established
    /// before returning the ActorEdgeSystem.
    ///
    /// - Parameter timeout: Maximum time to wait for readiness
    /// - Throws: GRPCTransportError if connection failed or timeout
    public func waitUntilReady(timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            // Check current state
            do {
                try readyStateMachine.checkReady()
                // If checkReady doesn't throw, we're ready
                logger.debug("gRPC transport ready")
                return
            } catch GRPCTransportError.connectionFailed(let error) {
                // Connection failed - propagate immediately
                throw GRPCTransportError.connectionFailed(error)
            } catch GRPCTransportError.notReady {
                // Still not ready - continue polling
            } catch {
                // Unknown error
                throw error
            }

            // Small delay between checks
            try await Task.sleep(for: .milliseconds(10))
        }

        throw GRPCTransportError.readinessTimeout
    }

    public func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Server-side: responses are sent back through gRPC response stream
        // This is handled by the DistributedActorService
        logger.trace("Response sent for callID: \(envelope.callID)")
    }

    public func close() async throws {
        logger.info("Closing gRPC transport")

        // Cancel the connection task and wait for it to complete
        if let task = connectionTask {
            task.cancel()

            // Wait for the task to finish (catches CancellationError)
            do {
                try await task.value
            } catch is CancellationError {
                // Expected - task was cancelled
                logger.debug("Connection task cancelled successfully")
            } catch {
                // Log but don't throw - best effort shutdown
                logger.warning("Connection task failed during shutdown: \(error)")
            }
        }

        // Finish the incoming invocations stream to prevent hanging tasks
        incomingContinuation.finish()

        logger.info("gRPC transport closed")
    }
}
