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
import GRPCCore

/// JSON deserializer for Codable types
///
/// This deserializer uses JSONDecoder to deserialize Codable messages from gRPC transmission.
/// It provides a bridge between gRPC's MessageDeserializer protocol and Swift's Codable protocol.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct JSONDeserializer<Message: Codable>: MessageDeserializer {
    private let decoder: JSONDecoder

    /// Creates a new JSON deserializer
    ///
    /// - Parameter decoder: Optional custom JSONDecoder. If not provided, uses default configuration.
    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    /// Deserializes JSON bytes to a Codable message
    ///
    /// - Parameter serializedMessageBytes: The JSON-encoded bytes to deserialize
    /// - Returns: The deserialized message
    /// - Throws: RPCError with code .internalError if deserialization fails
    public func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> Message {
        do {
            let data = serializedMessageBytes.withUnsafeBytes { Data($0) }
            return try decoder.decode(Message.self, from: data)
        } catch {
            throw RPCError(
                code: .internalError,
                message: "Failed to deserialize message from JSON: \(error)"
            )
        }
    }
}
