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

// Type aliases for clarity
public typealias ProtoEnvelope = ActorEdgeEnvelope  // Protobuf-generated type
public typealias ProtoActorID = ActorEdgeActorID    // Protobuf-generated type
public typealias ProtoManifest = ActorEdgeManifest  // Protobuf-generated type
public typealias ProtoMessageMetadata = ActorEdgeMessageMetadata  // Protobuf-generated type
public typealias ProtoMessageType = ActorEdgeMessageType  // Protobuf-generated type

/// Actor-edge equivalent of Wire.Envelope
///
/// This is the fundamental message structure for all actor communication,
/// providing transport-agnostic message delivery.
public struct Envelope: Sendable, Codable {
    /// Destination actor
    public let recipient: ActorEdgeID
    
    /// Source actor (optional for client-initiated requests)
    public let sender: ActorEdgeID?
    
    /// Serialization metadata
    public let manifest: SerializationManifest
    
    /// Serialized message data
    public let payload: Data
    
    /// Message metadata
    public let metadata: MessageMetadata
    
    /// Message type
    public let messageType: MessageType
    
    public init(
        recipient: ActorEdgeID,
        sender: ActorEdgeID? = nil,
        manifest: SerializationManifest,
        payload: Data,
        metadata: MessageMetadata,
        messageType: MessageType
    ) {
        self.recipient = recipient
        self.sender = sender
        self.manifest = manifest
        self.payload = payload
        self.metadata = metadata
        self.messageType = messageType
    }
}

/// Message metadata
public struct MessageMetadata: Sendable, Codable {
    /// Unique call identifier
    public let callID: String
    
    /// Method/target identifier
    public let target: String
    
    /// Message timestamp
    public let timestamp: Date
    
    /// Custom headers for extensibility
    public let headers: [String: String]
    
    public init(
        callID: String,
        target: String,
        timestamp: Date = Date(),
        headers: [String: String] = [:]
    ) {
        self.callID = callID
        self.target = target
        self.timestamp = timestamp
        self.headers = headers
    }
}

/// Message types
public enum MessageType: String, Sendable, Codable {
    case invocation  // Remote method invocation
    case response    // Method response
    case error       // Error response
    case system      // System message (for future use)
}

// MARK: - Convenience Factory Methods

extension Envelope {
    /// Creates an invocation envelope
    public static func invocation(
        to recipient: ActorEdgeID,
        from sender: ActorEdgeID? = nil,
        target: String,
        callID: String = UUID().uuidString,
        manifest: SerializationManifest,
        payload: Data,
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
            messageType: .invocation
        )
    }
    
    /// Creates a response envelope
    public static func response(
        to recipient: ActorEdgeID,
        from sender: ActorEdgeID? = nil,
        callID: String,
        manifest: SerializationManifest,
        payload: Data,
        headers: [String: String] = [:]
    ) -> Envelope {
        return Envelope(
            recipient: recipient,
            sender: sender,
            manifest: manifest,
            payload: payload,
            metadata: MessageMetadata(
                callID: callID,
                target: "",  // Responses don't have targets
                headers: headers
            ),
            messageType: .response
        )
    }
    
    /// Creates an error envelope
    public static func error(
        to recipient: ActorEdgeID,
        from sender: ActorEdgeID? = nil,
        callID: String,
        manifest: SerializationManifest,
        payload: Data,
        headers: [String: String] = [:]
    ) -> Envelope {
        return Envelope(
            recipient: recipient,
            sender: sender,
            manifest: manifest,
            payload: payload,
            metadata: MessageMetadata(
                callID: callID,
                target: "",  // Errors don't have targets
                headers: headers
            ),
            messageType: .error
        )
    }
}