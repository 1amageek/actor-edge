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

/// JSON serializer for Codable types
///
/// This serializer uses JSONEncoder to serialize Codable messages for gRPC transmission.
/// It provides a bridge between Swift's Codable protocol and gRPC's MessageSerializer protocol.
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct JSONSerializer<Message: Codable>: MessageSerializer {
    private let encoder: JSONEncoder

    /// Creates a new JSON serializer
    ///
    /// - Parameter encoder: Optional custom JSONEncoder. If not provided, uses default configuration.
    public init(encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = encoder
    }

    /// Serializes a Codable message to JSON bytes
    ///
    /// - Parameter message: The message to serialize
    /// - Returns: JSON-encoded bytes
    /// - Throws: RPCError with code .internalError if serialization fails
    public func serialize<Bytes: GRPCContiguousBytes>(_ message: Message) throws -> Bytes {
        do {
            let data = try encoder.encode(message)
            return Bytes(data)
        } catch {
            throw RPCError(
                code: .internalError,
                message: "Failed to serialize message to JSON: \(error)"
            )
        }
    }
}
