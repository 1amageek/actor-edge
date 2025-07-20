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

import Distributed
import Foundation
import Logging

/// Handler for distributed actor method invocation results.
///
/// This handler implements Swift Distributed's `DistributedTargetInvocationResultHandler`
/// protocol to process the results of distributed method calls, including successful
/// returns, void returns, and thrown errors.
public final class ActorEdgeResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = Codable & Sendable
    
    // MARK: - Internal State
    
    /// Current handler state
    private let state: HandlerState
    
    /// Reference to the actor system
    private let system: ActorEdgeSystem?
    
    /// Logger instance
    private let logger = Logger(label: "ActorEdge.ResultHandler")
    
    /// Completion flag to prevent double responses
    private var isCompleted: Bool = false
    
    // MARK: - Initialization
    
    /// Initialize for local direct return
    private init(continuation: CheckedContinuation<Any, Error>) {
        self.state = .localDirectReturn(continuation)
        self.system = nil
    }
    
    /// Initialize for remote call
    private init(
        system: ActorEdgeSystem,
        responseWriter: InvocationResponseWriter
    ) {
        self.state = .remoteCall(responseWriter: responseWriter)
        self.system = system
    }
    
    
    
    // MARK: - DistributedTargetInvocationResultHandler Implementation
    // Following swift-distributed-actors state-based pattern
    
    public func onReturn<Success>(
        value: Success
    ) async throws where Success: SerializationRequirement {
        guard !isCompleted else {
            logger.warning("ResultHandler.onReturn called but already completed - ignoring")
            return
        }
        isCompleted = true
        
        logger.debug("ResultHandler.onReturn called", metadata: [
            "type": "\(Success.self)"
        ])
        
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume the continuation with the value
            logger.debug("Resuming local continuation with value")
            continuation.resume(returning: value)
            
        case .remoteCall(let responseWriter):
            // For remote calls, serialize and send back
            logger.debug("Handling remote call return")
            
            guard let system = self.system else {
                logger.error("No system available for serialization")
                throw HandlerError.noSystemAvailable
            }
            
            do {
                let serialized = try system.serialization.serialize(value)
                let result = InvocationResult.success(serialized)
                try await responseWriter.sendResult(result)
                logger.debug("Success response written")
            } catch {
                logger.error("Failed to serialize return value", metadata: [
                    "error": "\(error)"
                ])
                // Send serialization error
                try await responseWriter.sendError(error)
            }
        }
    }
    
    public func onReturnVoid() async throws {
        guard !isCompleted else {
            logger.warning("ResultHandler.onReturnVoid called but already completed - ignoring")
            return
        }
        isCompleted = true
        
        logger.debug("ResultHandler.onReturnVoid called")
        
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume with empty tuple
            logger.debug("Resuming local continuation with void")
            continuation.resume(returning: ())
            
        case .remoteCall(let responseWriter):
            // For remote calls, send void result
            logger.debug("Writing void response")
            
            let result = InvocationResult.void
            try await responseWriter.sendResult(result)
            logger.debug("Void response written")
        }
    }
    
    public func onThrow<Err: Error>(
        error: Err
    ) async throws {
        guard !isCompleted else {
            logger.warning("ResultHandler.onThrow called but already completed - ignoring")
            return
        }
        isCompleted = true
        
        logger.error("ResultHandler.onThrow called", metadata: [
            "error": "\(error)",
            "errorType": "\(type(of: error))"
        ])
        
        switch state {
        case .localDirectReturn(let continuation):
            // For local calls, resume by throwing the error
            logger.debug("Resuming local continuation with error")
            continuation.resume(throwing: error)
            
        case .remoteCall(let responseWriter):
            // For remote calls, send error
            logger.debug("Writing error response")
            try await responseWriter.sendError(error)
            logger.debug("Error response written")
        }
    }
    
}

// MARK: - Supporting Types

/// Handler state
private enum HandlerState {
    case localDirectReturn(CheckedContinuation<Any, Error>)
    case remoteCall(responseWriter: InvocationResponseWriter)
}

/// Handler-specific errors
private enum HandlerError: Error {
    case noSystemAvailable
}

// MARK: - Factory Methods

extension ActorEdgeResultHandler {
    /// Create a result handler for local direct returns
    public static func forLocalReturn(
        continuation: CheckedContinuation<Any, Error>
    ) -> ActorEdgeResultHandler {
        return ActorEdgeResultHandler(continuation: continuation)
    }
    
    /// Create a result handler for remote calls
    public static func forRemoteCall(
        system: ActorEdgeSystem,
        callID: String,
        responseWriter: InvocationResponseWriter
    ) -> ActorEdgeResultHandler {
        return ActorEdgeResultHandler(
            system: system,
            responseWriter: responseWriter
        )
    }
}