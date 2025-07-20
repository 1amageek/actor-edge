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
import SwiftProtobuf

// MARK: - ActorEdgeID Conversions

extension ActorEdgeID {
    /// Creates from protobuf representation
    init(from proto: ProtoActorID) {
        self.init(proto.value, metadata: proto.metadata)
    }
    
    /// Converts to protobuf representation
    func toProto() -> ProtoActorID {
        var proto = ProtoActorID()
        proto.value = self.description
        proto.metadata = self.metadata
        return proto
    }
}

// MARK: - Envelope Conversions

extension Envelope {
    /// Creates from protobuf representation
    init(from proto: ProtoEnvelope) throws {
        guard proto.hasRecipient else {
            throw ActorEdgeError.invalidEnvelope("Missing recipient")
        }
        
        self.init(
            recipient: ActorEdgeID(from: proto.recipient),
            sender: proto.hasSender ? ActorEdgeID(from: proto.sender) : nil,
            manifest: try SerializationManifest(from: proto.manifest),
            payload: proto.payload,
            metadata: MessageMetadata(from: proto.metadata),
            messageType: MessageType(from: proto.type)
        )
    }
    
    /// Converts to protobuf representation
    func toProto() -> ProtoEnvelope {
        var proto = ProtoEnvelope()
        proto.recipient = recipient.toProto()
        if let sender = sender {
            proto.sender = sender.toProto()
        }
        proto.manifest = manifest.toProto()
        proto.payload = payload
        proto.metadata = metadata.toProto()
        proto.type = messageType.toProto()
        return proto
    }
}

// MARK: - MessageMetadata Conversions

extension MessageMetadata {
    /// Creates from protobuf representation
    init(from proto: ProtoMessageMetadata) {
        self.init(
            callID: proto.callID,
            target: proto.target,
            timestamp: Date(timeIntervalSince1970: TimeInterval(proto.timestamp)),
            headers: proto.headers
        )
    }
    
    /// Converts to protobuf representation
    func toProto() -> ProtoMessageMetadata {
        var proto = ProtoMessageMetadata()
        proto.callID = callID
        proto.target = target
        proto.timestamp = Int64(timestamp.timeIntervalSince1970)
        proto.headers = headers
        return proto
    }
}

// MARK: - MessageType Conversions

extension MessageType {
    /// Creates from protobuf representation
    init(from proto: ProtoMessageType) {
        switch proto {
        case .invocation:
            self = .invocation
        case .response:
            self = .response
        case .error:
            self = .error
        case .system:
            self = .system
        case .unknown, .UNRECOGNIZED:
            self = .system  // Default to system for unknown types
        }
    }
    
    /// Converts to protobuf representation
    func toProto() -> ProtoMessageType {
        switch self {
        case .invocation:
            return .invocation
        case .response:
            return .response
        case .error:
            return .error
        case .system:
            return .system
        }
    }
}

// MARK: - SerializationManifest Conversions

extension SerializationManifest {
    /// Creates from protobuf representation
    init(from proto: ProtoManifest) throws {
        guard !proto.serializerID.isEmpty else {
            throw ActorEdgeError.invalidEnvelope("Missing serializer ID")
        }
        
        self.init(
            serializerID: proto.serializerID,
            hint: proto.typeHint
        )
    }
    
    /// Converts to protobuf representation
    func toProto() -> ProtoManifest {
        var proto = ProtoManifest()
        proto.serializerID = serializerID
        proto.typeHint = hint
        return proto
    }
}

// MARK: - InvocationData Conversions

extension InvocationData {
    /// Creates from protobuf representation
    init(from proto: ActorEdgeInvocationData) throws {
        var arguments: [Data] = []
        for arg in proto.arguments {
            arguments.append(arg.data)
        }
        
        self.init(
            arguments: arguments,
            genericSubstitutions: proto.genericSubstitutions,
            isVoid: proto.isVoid
        )
    }
    
    /// Converts to protobuf representation
    func toProto() -> ActorEdgeInvocationData {
        var proto = ActorEdgeInvocationData()
        
        for (index, arg) in arguments.enumerated() {
            var serializedArg = ActorEdgeSerializedArgument()
            serializedArg.data = arg
            if index < argumentManifests.count {
                serializedArg.manifest = argumentManifests[index].toProto()
            }
            proto.arguments.append(serializedArg)
        }
        
        proto.genericSubstitutions = genericSubstitutions
        proto.isVoid = isVoid
        
        return proto
    }
}

// MARK: - ResponseData Conversions

/// Response data structure for method results
public struct ResponseData: Sendable, Codable {
    public enum Result: Sendable, Codable {
        case success(Data)
        case error(SerializedError)
        case void
    }
    
    public let result: Result
    public let manifest: SerializationManifest?
    
    public init(result: Result, manifest: SerializationManifest? = nil) {
        self.result = result
        self.manifest = manifest
    }
}

extension ResponseData {
    /// Creates from protobuf representation
    init(from proto: ActorEdgeResponseData) throws {
        let manifest = proto.hasManifest ? try SerializationManifest(from: proto.manifest) : nil
        
        switch proto.result {
        case .successData(let data):
            self.init(result: .success(data), manifest: manifest)
        case .error(let errorData):
            self.init(
                result: .error(SerializedError(from: errorData)),
                manifest: manifest
            )
        case .void:
            self.init(result: .void, manifest: manifest)
        case .none:
            throw ActorEdgeError.invalidEnvelope("Missing response result")
        }
    }
    
    /// Converts to protobuf representation
    func toProto() -> ActorEdgeResponseData {
        var proto = ActorEdgeResponseData()
        
        switch result {
        case .success(let data):
            proto.successData = data
        case .error(let error):
            proto.error = error.toProto()
        case .void:
            proto.void = ActorEdgeVoidResult()
        }
        
        if let manifest = manifest {
            proto.manifest = manifest.toProto()
        }
        
        return proto
    }
}

// MARK: - SerializedError Conversions

extension SerializedError {
    /// Creates from protobuf representation
    init(from proto: ActorEdgeErrorData) {
        self.init(
            type: proto.type,
            message: proto.message,
            serializedError: proto.serializedError.isEmpty ? nil : proto.serializedError
        )
    }
    
    /// Converts to protobuf representation
    func toProto() -> ActorEdgeErrorData {
        var proto = ActorEdgeErrorData()
        proto.type = type
        proto.message = message
        if let serializedError = serializedError {
            proto.serializedError = serializedError
        }
        return proto
    }
}