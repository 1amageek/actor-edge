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

import ActorEdgeCore
import ActorRuntime
import Distributed
import Foundation
import GRPCCore
import Logging

/// gRPC service that handles distributed actor method invocations.
///
/// This service receives InvocationEnvelope messages via gRPC and dispatches them
/// to the appropriate distributed actors using Swift's distributed actor runtime.
/// It uses JSON serialization for ActorRuntime's Codable envelopes.
public struct DistributedActorService: RegistrableRPCService {
    private let system: ActorEdgeSystem
    private let logger: Logger

    public init(system: ActorEdgeSystem, logger: Logger = Logger(label: "ActorEdge.Service")) {
        self.system = system
        self.logger = logger
    }

    public func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        // Register the RemoteCall RPC method with JSON serialization
        router.registerHandler(
            forMethod: MethodDescriptor(
                service: ServiceDescriptor(fullyQualifiedService: "DistributedActor"),
                method: "RemoteCall"
            ),
            deserializer: JSONDeserializer<InvocationEnvelope>(),
            serializer: JSONSerializer<ResponseEnvelope>(),
            handler: { request, context in
                try await self.handleRemoteCall(request: request, context: context)
            }
        )
    }

    /// Handles a remote call request.
    private func handleRemoteCall(
        request: StreamingServerRequest<InvocationEnvelope>,
        context: ServerContext
    ) async throws -> StreamingServerResponse<ResponseEnvelope> {
        // Get the single message from the stream
        guard let invocationEnvelope = try await request.messages.first(where: { _ in true }) else {
            throw ActorRuntime.RuntimeError.invalidEnvelope("No invocation envelope received")
        }

        logger.debug("Handling remote call", metadata: [
            "callID": "\(invocationEnvelope.callID)",
            "recipient": "\(invocationEnvelope.recipientID)",
            "target": "\(invocationEnvelope.target)"
        ])

        // Execute the invocation and get response
        let responseEnvelope = try await executeInvocation(invocationEnvelope)

        // Return single response wrapped in ServerResponse
        let serverResponse = ServerResponse(message: responseEnvelope)
        return StreamingServerResponse(single: serverResponse)
    }

    /// Executes a distributed actor invocation.
    private func executeInvocation(_ envelope: InvocationEnvelope) async throws -> ResponseEnvelope {
        let startTime = Date()

        // Find the target actor
        let actorID = ActorEdgeID(envelope.recipientID)
        guard let actor = system.findActor(id: actorID) else {
            logger.error("Actor not found", metadata: ["actorID": "\(envelope.recipientID)"])
            throw ActorRuntime.RuntimeError.actorNotFound(envelope.recipientID)
        }

        // Create decoder from envelope
        var decoder = try CodableInvocationDecoder(envelope: envelope)

        // Create result handler that will be called by executeDistributedTarget
        var capturedResponse: ResponseEnvelope?
        let resultHandler = CodableResultHandler(callID: envelope.callID) { responseEnvelope in
            // Add execution time metadata using convenience method
            let executionTime = Date().timeIntervalSince(startTime)
            capturedResponse = responseEnvelope.withExecutionTime(executionTime)
        }

        // Create remote call target
        let target = RemoteCallTarget(envelope.target)

        logger.debug("Executing distributed target", metadata: [
            "actor": "\(type(of: actor))",
            "method": "\(envelope.target)"
        ])

        // Execute the distributed target using Swift runtime
        // This will synchronously call the resultHandler's onReturn/onReturnVoid/onThrow
        do {
            try await system.executeDistributedTarget(
                on: actor,
                target: target,
                invocationDecoder: &decoder,
                handler: resultHandler
            )

            // Return the captured response
            guard let response = capturedResponse else {
                throw ActorRuntime.RuntimeError.executionFailed(
                    "No response captured from result handler",
                    underlying: "Internal error"
                )
            }
            return response

        } catch {
            // If executeDistributedTarget itself throws (not the method execution),
            // create an error response
            logger.error("Failed to execute distributed target", metadata: [
                "callID": "\(envelope.callID)",
                "error": "\(error)"
            ])

            let executionTime = Date().timeIntervalSince(startTime)
            let runtimeError: ActorRuntime.RuntimeError
            if let err = error as? ActorRuntime.RuntimeError {
                runtimeError = err
            } else {
                runtimeError = .executionFailed(
                    String(describing: error),
                    underlying: String(reflecting: error)
                )
            }

            return ResponseEnvelope(
                callID: envelope.callID,
                result: .failure(runtimeError)
            ).withExecutionTime(executionTime)
        }
    }
}
