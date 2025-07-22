import Testing
import Foundation
@testable import ActorEdgeCore
import Distributed

/// Centralized test utilities for ActorEdge
public struct TestHelpers {
    /// Test timeout duration
    public static let testTimeout: Duration = .seconds(30)
    
    /// Create a test actor system
    public static func makeTestActorSystem(namespace: String = "test") -> ActorEdgeSystem {
        ActorEdgeSystem(metricsNamespace: namespace)
    }
    
    /// Create connected client-server pair
    public static func makeConnectedPair() -> (client: ActorEdgeSystem, server: ActorEdgeSystem) {
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        let client = ActorEdgeSystem(transport: clientTransport, metricsNamespace: "test_client")
        let server = ActorEdgeSystem(metricsNamespace: "test_server")
        
        // Set up server to handle messages with full distributed actor processing
        Task {
            for await envelope in serverTransport.receive() {
                do {
                    guard envelope.messageType == .invocation else { continue }
                    
                    // Find the actor
                    guard let actor = server.findActor(id: envelope.recipient) else {
                        let errorData = try server.serialization.serialize(
                            ActorEdgeError.actorNotFound(envelope.recipient)
                        )
                        let errorResponse = Envelope.error(
                            to: envelope.sender ?? envelope.recipient,
                            callID: envelope.metadata.callID,
                            manifest: errorData.manifest,
                            payload: errorData.data
                        )
                        _ = try await serverTransport.send(errorResponse)
                        continue
                    }
                    
                    // Create decoder
                    let invocationData = try server.serialization.deserialize(
                        envelope.payload,
                        as: InvocationData.self,
                        using: envelope.manifest
                    )
                    var decoder = ActorEdgeInvocationDecoder(
                        system: server,
                        invocationData: invocationData
                    )
                    
                    // Create response writer
                    let responseWriter = InvocationResponseWriter(
                        processor: DistributedInvocationProcessor(
                            serialization: server.serialization
                        ),
                        transport: serverTransport,
                        recipient: envelope.sender ?? envelope.recipient,
                        correlationID: envelope.metadata.callID,
                        sender: envelope.recipient
                    )
                    
                    // Create result handler for remote call
                    let resultHandler = ActorEdgeResultHandler.forRemoteCall(
                        system: server,
                        callID: envelope.metadata.callID,
                        responseWriter: responseWriter
                    )
                    
                    // Execute the distributed target
                    try await server.executeDistributedTarget(
                        on: actor,
                        target: RemoteCallTarget(envelope.metadata.target),
                        invocationDecoder: &decoder,
                        handler: resultHandler
                    )
                } catch {
                    // Send error response
                    let errorData = try? server.serialization.serialize(
                        ActorEdgeError.invocationError("Remote call failed: \(error)")
                    )
                    if let errorData = errorData {
                        let errorResponse = Envelope.error(
                            to: envelope.sender ?? envelope.recipient,
                            callID: envelope.metadata.callID,
                            manifest: errorData.manifest,
                            payload: errorData.data
                        )
                        _ = try? await serverTransport.send(errorResponse)
                    }
                }
            }
        }
        
        return (client, server)
    }
    
    /// Wait for async condition with timeout
    public static func waitForCondition(
        timeout: Duration = testTimeout,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () async throws -> Bool
    ) async throws {
        let start = ContinuousClock.now
        while start.duration(to: ContinuousClock.now) < timeout {
            if try await condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("Condition not met within timeout")
    }
    
    /// Create test envelope
    public static func makeTestEnvelope(
        to recipient: ActorEdgeID = ActorEdgeID("test-actor"),
        from sender: ActorEdgeID? = ActorEdgeID("test-sender"),
        type: MessageType = .invocation,
        target: String = "testMethod",
        payload: Data = Data("test".utf8)
    ) -> Envelope {
        let metadata = MessageMetadata(
            callID: UUID().uuidString,
            target: target,
            headers: [:]
        )
        
        return Envelope(
            recipient: recipient,
            sender: sender,
            manifest: SerializationManifest.json(),
            payload: payload,
            metadata: metadata,
            messageType: type
        )
    }
    
    /// Assert envelope equality
    public static func assertEnvelopeEqual(
        _ actual: Envelope,
        _ expected: Envelope,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // SourceLocation API has changed, we'll remove custom location
        
        #expect(actual.recipient == expected.recipient, 
               "Recipients don't match")
        #expect(actual.sender == expected.sender, 
               "Senders don't match")
        #expect(actual.messageType == expected.messageType, 
               "Message types don't match")
        #expect(actual.metadata.target == expected.metadata.target, 
               "Targets don't match")
        #expect(actual.payload == expected.payload, 
               "Payloads don't match")
    }
    
    // Removed makeServerWithActor as it cannot be implemented generically
    // Each test should create actors directly with their specific types
    
    /// Create envelope factory for testing
    public struct EnvelopeFactory {
        
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
}

// MARK: - Duration Extension

extension Duration {
    public var timeInterval: TimeInterval {
        let nanoseconds = components.attoseconds / 1_000_000_000
        let seconds = TimeInterval(components.seconds)
        let fractional = TimeInterval(nanoseconds) / 1_000_000_000
        return seconds + fractional
    }
}

