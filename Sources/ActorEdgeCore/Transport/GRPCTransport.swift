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
import Logging

/// gRPC implementation of ActorRuntime's DistributedTransport protocol
///
/// This transport uses JSON serialization to send ActorRuntime's InvocationEnvelope
/// and ResponseEnvelope directly over gRPC, without intermediate protobuf conversion.
public final class GRPCTransport: DistributedTransport, Sendable {
    private let client: GRPCClient<HTTP2ClientTransport.Posix>
    private let logger: Logger

    /// Incoming invocations stream continuation
    private let incomingContinuation: AsyncStream<InvocationEnvelope>.Continuation

    /// Public stream of incoming invocations
    public let incomingInvocations: AsyncStream<InvocationEnvelope>

    public init(client: GRPCClient<HTTP2ClientTransport.Posix>, logger: Logger = Logger(label: "ActorEdge.GRPCTransport")) {
        self.client = client
        self.logger = logger

        var continuation: AsyncStream<InvocationEnvelope>.Continuation!
        self.incomingInvocations = AsyncStream { cont in
            continuation = cont
        }
        self.incomingContinuation = continuation
    }

    public func sendInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        logger.trace("Sending invocation", metadata: ["callID": "\(envelope.callID)"])

        // Create method descriptor
        let method = MethodDescriptor(
            service: ServiceDescriptor(fullyQualifiedService: "DistributedActor"),
            method: "RemoteCall"
        )

        // Make gRPC unary call with JSON serialization
        let response: ResponseEnvelope = try await client.unary(
            request: ClientRequest(message: envelope),
            descriptor: method,
            serializer: JSONSerializer<InvocationEnvelope>(),
            deserializer: JSONDeserializer<ResponseEnvelope>(),
            options: .defaults
        ) { response in
            return try response.message
        }

        logger.trace("Received response", metadata: ["callID": "\(response.callID)"])
        return response
    }

    public func sendResponse(_ envelope: ResponseEnvelope) async throws {
        // Server-side: responses are sent back through gRPC response stream
        // This is handled by the DistributedActorService
        logger.trace("Response sent for callID: \(envelope.callID)")
    }

    public func close() async throws {
        logger.info("Closing gRPC transport")
        incomingContinuation.finish()
        // GRPCClient doesn't have a close method in grpc-swift 2.0
        // The client will be closed when it's deallocated
    }
}
