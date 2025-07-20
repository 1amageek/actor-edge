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
import Distributed

/// Processes distributed method invocations by converting between
/// Swift Distributed's invocation system and ActorEdge's envelope-based messaging.
public final class DistributedInvocationProcessor: Sendable {
    private let serialization: SerializationSystem
    
    /// Creates a new invocation processor.
    public init(serialization: SerializationSystem) {
        self.serialization = serialization
    }
    
    /// Creates an invocation envelope from an encoder.
    public func createInvocationEnvelope(
        recipient: ActorEdgeID,
        target: RemoteCallTarget,
        encoder: ActorEdgeInvocationEncoder,
        sender: ActorEdgeID? = nil,
        traceContext: [String: String] = [:]
    ) throws -> Envelope {
        let invocationData = try encoder.finalizeInvocation()
        let serialized = try serialization.serialize(invocationData)
        
        return Envelope.invocation(
            to: recipient,
            from: sender,
            target: target.identifier,
            manifest: serialized.manifest,
            payload: serialized.data,
            headers: traceContext
        )
    }
    
    /// Creates an invocation decoder from an envelope.
    public func createInvocationDecoder(
        from envelope: Envelope,
        system: ActorEdgeSystem
    ) throws -> ActorEdgeInvocationDecoder {
        guard envelope.messageType == .invocation else {
            throw InvocationError.invalidMessageType(
                expected: .invocation,
                actual: envelope.messageType
            )
        }
        
        let invocationData = try serialization.deserialize(
            envelope.payload,
            as: InvocationData.self,
            using: envelope.manifest
        )
        
        return ActorEdgeInvocationDecoder(
            system: system,
            invocationData: invocationData,
            envelope: envelope
        )
    }
    
    /// Creates a response envelope from a result.
    public func createResponseEnvelope(
        to recipient: ActorEdgeID,
        correlationID: String,
        result: InvocationResult,
        sender: ActorEdgeID? = nil
    ) throws -> Envelope {
        let serialized = try serialization.serialize(result)
        
        return Envelope.response(
            to: recipient,
            from: sender,
            callID: correlationID,
            manifest: serialized.manifest,
            payload: serialized.data
        )
    }
    
    /// Creates an error envelope from an error.
    public func createErrorEnvelope(
        to recipient: ActorEdgeID,
        correlationID: String,
        error: Error,
        sender: ActorEdgeID? = nil
    ) throws -> Envelope {
        let serializedError: SerializedError
        
        // Try to serialize the error if it's Codable
        if let codableError = error as? (any Codable & Error) {
            do {
                let serialized = try serialization.serialize(codableError)
                serializedError = SerializedError(
                    type: String(reflecting: type(of: error)),
                    message: String(describing: error),
                    serializedError: serialized.data
                )
            } catch {
                // Fallback to string representation
                serializedError = createFallbackError(error)
            }
        } else {
            serializedError = createFallbackError(error)
        }
        
        let result = InvocationResult.error(serializedError)
        let serialized = try serialization.serialize(result)
        
        return Envelope.error(
            to: recipient,
            from: sender,
            callID: correlationID,
            manifest: serialized.manifest,
            payload: serialized.data
        )
    }
    
    /// Extracts the invocation result from a response envelope.
    public func extractResult(
        from envelope: Envelope
    ) throws -> InvocationResult {
        guard envelope.messageType == .response || envelope.messageType == .error else {
            throw InvocationError.invalidMessageType(
                expected: .response,
                actual: envelope.messageType
            )
        }
        
        return try serialization.deserialize(
            envelope.payload,
            as: InvocationResult.self,
            using: envelope.manifest
        )
    }
    
    private func createFallbackError(_ error: Error) -> SerializedError {
        let errorInfo = [
            "type": String(reflecting: type(of: error)),
            "description": String(describing: error)
        ]
        
        let data = try! JSONEncoder().encode(errorInfo)
        
        return SerializedError(
            type: String(reflecting: type(of: error)),
            message: String(describing: error),
            serializedError: data
        )
    }
}

/// Errors that can occur during invocation processing.
public enum InvocationError: Error, Sendable {
    case invalidMessageType(expected: MessageType, actual: MessageType)
    case missingTarget
    case missingCorrelationID
    case serializationFailed(Error)
    case deserializationFailed(Error)
}

// MARK: - Result Handler Support

extension DistributedInvocationProcessor {
    /// Creates a response writer for handling invocation results.
    public func createResponseWriter(
        for envelope: Envelope,
        transport: MessageTransport
    ) -> InvocationResponseWriter {
        return InvocationResponseWriter(
            processor: self,
            transport: transport,
            recipient: envelope.sender ?? envelope.recipient,
            correlationID: envelope.metadata.callID,
            sender: envelope.recipient
        )
    }
}

/// Handles writing invocation responses back through the transport.
public final class InvocationResponseWriter: Sendable {
    private let processor: DistributedInvocationProcessor
    private let transport: MessageTransport
    private let recipient: ActorEdgeID
    private let correlationID: String
    private let sender: ActorEdgeID
    
    init(
        processor: DistributedInvocationProcessor,
        transport: MessageTransport,
        recipient: ActorEdgeID,
        correlationID: String,
        sender: ActorEdgeID
    ) {
        self.processor = processor
        self.transport = transport
        self.recipient = recipient
        self.correlationID = correlationID
        self.sender = sender
    }
    
    /// Sends a successful result.
    public func sendResult(_ result: InvocationResult) async throws {
        let envelope = try processor.createResponseEnvelope(
            to: recipient,
            correlationID: correlationID,
            result: result,
            sender: sender
        )
        
        _ = try await transport.send(envelope)
    }
    
    /// Sends an error.
    public func sendError(_ error: Error) async throws {
        let envelope = try processor.createErrorEnvelope(
            to: recipient,
            correlationID: correlationID,
            error: error,
            sender: sender
        )
        
        _ = try await transport.send(envelope)
    }
}