import Testing
@testable import ActorEdgeCore
import Distributed
import Foundation

@Suite("Error Handling Tests", .tags(.integration, .errorHandling))
struct ErrorHandlingTests {
    
    // MARK: - Custom Error Types for Testing
    
    enum CustomError: Error, Codable, Sendable, Equatable {
        case businessLogicError(code: Int, message: String)
        case validationError(field: String, reason: String)
        case authenticationError
        case authorizationError(resource: String)
        case rateLimitExceeded(retryAfter: Int)
        case resourceNotFound(id: String)
        case conflictError(existingId: String)
        case internalServerError(details: String)
    }
    
    struct DetailedError: Error, Codable, Sendable, Equatable {
        let id: UUID
        let timestamp: Date
        let category: String
        let severity: ErrorSeverity
        let message: String
        let stackTrace: [String]?
        let metadata: [String: String]
        
        enum ErrorSeverity: String, Codable, Sendable, Equatable {
            case debug, info, warning, error, critical
        }
        
        init(
            id: UUID = UUID(),
            timestamp: Date = Date(),
            category: String,
            severity: ErrorSeverity,
            message: String,
            stackTrace: [String]? = nil,
            metadata: [String: String] = [:]
        ) {
            self.id = id
            self.timestamp = timestamp
            self.category = category
            self.severity = severity
            self.message = message
            self.stackTrace = stackTrace
            self.metadata = metadata
        }
    }
    
    // MARK: - Error Handling Test Actor
    
    @Resolvable
    protocol ErrorHandlingActor: DistributedActor where ActorSystem == ActorEdgeSystem {
        distributed func throwCustomError(_ error: CustomError) async throws
        distributed func throwDetailedError(_ error: DetailedError) async throws
        distributed func throwAfterDelay(delayMS: Int, error: CustomError) async throws
        distributed func throwRandomError() async throws -> String
        distributed func cascadeError(depth: Int) async throws
        distributed func throwNonCodableError() async throws
        distributed func recoverableOperation(shouldFail: Bool) async throws -> String
        distributed func batchOperationWithErrors(_ items: [String]) async throws -> [Result<String, CustomError>]
    }
    
    distributed actor ErrorHandlingActorImpl: ErrorHandlingActor {
        typealias ActorSystem = ActorEdgeSystem
        
        private var errorCount = 0
        
        init(actorSystem: ActorSystem) {
            self.actorSystem = actorSystem
        }
        
        distributed func throwCustomError(_ error: CustomError) async throws {
            errorCount += 1
            throw error
        }
        
        distributed func throwDetailedError(_ error: DetailedError) async throws {
            errorCount += 1
            throw error
        }
        
        distributed func throwAfterDelay(delayMS: Int, error: CustomError) async throws {
            try await Task.sleep(for: .milliseconds(delayMS))
            errorCount += 1
            throw error
        }
        
        distributed func throwRandomError() async throws -> String {
            let errors: [CustomError] = [
                .businessLogicError(code: 400, message: "Invalid input"),
                .validationError(field: "email", reason: "Invalid format"),
                .authenticationError,
                .rateLimitExceeded(retryAfter: 60)
            ]
            
            let randomIndex = Int.random(in: 0..<errors.count)
            errorCount += 1
            throw errors[randomIndex]
        }
        
        distributed func cascadeError(depth: Int) async throws {
            guard depth > 0 else {
                throw CustomError.internalServerError(details: "Maximum depth reached")
            }
            
            do {
                try await cascadeError(depth: depth - 1)
            } catch {
                // Wrap and rethrow
                throw CustomError.internalServerError(
                    details: "Cascade error at depth \(depth): \(error)"
                )
            }
        }
        
        distributed func throwNonCodableError() async throws {
            struct NonCodableError: Error {
                let closure: () -> Void = {}
            }
            throw NonCodableError()
        }
        
        distributed func recoverableOperation(shouldFail: Bool) async throws -> String {
            if shouldFail {
                errorCount += 1
                throw CustomError.businessLogicError(code: 503, message: "Service temporarily unavailable")
            }
            return "Operation succeeded"
        }
        
        distributed func batchOperationWithErrors(_ items: [String]) async throws -> [Result<String, CustomError>] {
            return items.map { item in
                if item.contains("error") {
                    errorCount += 1
                    return .failure(.validationError(field: "item", reason: "Contains 'error'"))
                } else if item.isEmpty {
                    errorCount += 1
                    return .failure(.validationError(field: "item", reason: "Empty string"))
                } else {
                    return .success("Processed: \(item)")
                }
            }
        }
    }
    
    // MARK: - Tests
    
    @Test("Basic error propagation")
    func basicErrorPropagation() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        // Test simple custom error
        let customError = CustomError.businessLogicError(code: 404, message: "Not found")
        await #expect(throws: CustomError.self) {
            try await remoteActor.throwCustomError(customError)
        }
        
        // Test authentication error
        await #expect(throws: CustomError.self) {
            try await remoteActor.throwCustomError(.authenticationError)
        }
        
        // Test validation error
        let validationError = CustomError.validationError(field: "username", reason: "Too short")
        do {
            try await remoteActor.throwCustomError(validationError)
            Issue.record("Expected error was not thrown")
        } catch let error as CustomError {
            #expect(error == validationError)
        }
    }
    
    @Test("Detailed error propagation")
    func detailedErrorPropagation() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["detailed-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        let detailedError = DetailedError(
            category: "Database",
            severity: .critical,
            message: "Connection pool exhausted",
            stackTrace: ["DB.connect()", "Pool.acquire()", "main()"],
            metadata: ["pool_size": "100", "active_connections": "100"]
        )
        
        do {
            try await remoteActor.throwDetailedError(detailedError)
            Issue.record("Expected error was not thrown")
        } catch let error as DetailedError {
            #expect(error.category == detailedError.category)
            #expect(error.severity == detailedError.severity)
            #expect(error.message == detailedError.message)
            #expect(error.stackTrace == detailedError.stackTrace)
            #expect(error.metadata == detailedError.metadata)
        }
    }
    
    @Test("Error after delay")
    func errorAfterDelay() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["delayed-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        let startTime = ContinuousClock.now
        let error = CustomError.rateLimitExceeded(retryAfter: 30)
        
        await #expect(throws: CustomError.self) {
            try await remoteActor.throwAfterDelay(delayMS: 200, error: error)
        }
        
        let duration = startTime.duration(to: ContinuousClock.now)
        #expect(duration >= .milliseconds(200), "Error should be thrown after delay")
    }
    
    @Test("Cascading errors")
    func cascadingErrors() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["cascade-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        do {
            try await remoteActor.cascadeError(depth: 3)
            Issue.record("Expected cascading error was not thrown")
        } catch let error as CustomError {
            guard case .internalServerError(let details) = error else {
                Issue.record("Expected internal server error")
                return
            }
            #expect(details.contains("Cascade error at depth"))
        }
    }
    
    @Test("Non-codable error handling")
    func nonCodableErrorHandling() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["non-codable-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        // Non-codable errors should be wrapped or converted
        await #expect(throws: Error.self) {
            try await remoteActor.throwNonCodableError()
        }
    }
    
    @Test("Error recovery patterns")
    func errorRecoveryPatterns() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["recovery-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        // Test retry pattern
        var attempts = 0
        var lastError: Error?
        
        for _ in 0..<3 {
            do {
                let result = try await remoteActor.recoverableOperation(shouldFail: attempts < 2)
                #expect(result == "Operation succeeded")
                break
            } catch {
                lastError = error
                attempts += 1
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        
        #expect(attempts == 2, "Should have retried twice before succeeding")
    }
    
    @Test("Batch operations with partial errors")
    func batchOperationsWithPartialErrors() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["batch-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        let items = ["valid1", "error-item", "", "valid2", "another-error"]
        let results = try await remoteActor.batchOperationWithErrors(items)
        
        #expect(results.count == items.count)
        
        var successCount = 0
        var failureCount = 0
        
        for (index, result) in results.enumerated() {
            switch result {
            case .success(let value):
                successCount += 1
                #expect(value.hasPrefix("Processed:"))
            case .failure(let error):
                failureCount += 1
                if items[index].contains("error") {
                    guard case .validationError(_, let reason) = error else {
                        Issue.record("Expected validation error for error item")
                        continue
                    }
                    #expect(reason == "Contains 'error'")
                } else if items[index].isEmpty {
                    guard case .validationError(_, let reason) = error else {
                        Issue.record("Expected validation error for empty item")
                        continue
                    }
                    #expect(reason == "Empty string")
                }
            }
        }
        
        #expect(successCount == 2)
        #expect(failureCount == 3)
    }
    
    @Test("Concurrent error handling", .timeLimit(.minutes(1)))
    func concurrentErrorHandling() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["concurrent-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        let concurrentCalls = 20
        var errorTypes: Set<String> = []
        
        await withTaskGroup(of: Result<String, Error>.self) { group in
            for _ in 0..<concurrentCalls {
                group.addTask {
                    do {
                        return .success(try await remoteActor.throwRandomError())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            
            for await result in group {
                switch result {
                case .success:
                    Issue.record("Expected error but got success")
                case .failure(let error):
                    errorTypes.insert(String(describing: type(of: error)))
                }
            }
        }
        
        // Should have encountered various error types
        #expect(!errorTypes.isEmpty, "Should have encountered errors")
    }
    
    @Test("Error context preservation")
    func errorContextPreservation() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["context-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        // Create error with rich context
        let errorID = UUID()
        let timestamp = Date()
        let detailedError = DetailedError(
            id: errorID,
            timestamp: timestamp,
            category: "Authentication",
            severity: .error,
            message: "Invalid credentials",
            stackTrace: ["Auth.validate()", "Login.submit()"],
            metadata: [
                "user_id": "12345",
                "ip_address": "192.168.1.1",
                "attempt_count": "3"
            ]
        )
        
        do {
            try await remoteActor.throwDetailedError(detailedError)
        } catch let error as DetailedError {
            // Verify all context is preserved
            #expect(error.id == errorID)
            #expect(abs(error.timestamp.timeIntervalSince(timestamp)) < 1.0) // Within 1 second
            #expect(error.metadata["user_id"] == "12345")
            #expect(error.metadata["ip_address"] == "192.168.1.1")
            #expect(error.metadata["attempt_count"] == "3")
        }
    }
    
    @Test("Transport-level error handling")
    func transportLevelErrorHandling() async throws {
        let mockTransport = MockMessageTransport()
        let system = ActorEdgeSystem(transport: mockTransport, metricsNamespace: "error-test")
        
        system.setPreAssignedIDs(["transport-error-actor"])
        let actor = ErrorHandlingActorImpl(actorSystem: system)
        
        // Configure transport to fail
        mockTransport.shouldThrowError = true
        mockTransport.errorToThrow = TransportError.connectionFailed(reason: "Network unreachable")
        
        // Create remote reference
        let clientTransport = MockMessageTransport()
        clientTransport.shouldThrowError = true
        clientTransport.errorToThrow = TransportError.connectionFailed(reason: "Network unreachable")
        
        let clientSystem = ActorEdgeSystem(transport: clientTransport, metricsNamespace: "error-client")
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: clientSystem)
        
        // Should get transport error
        await #expect(throws: Error.self) {
            try await remoteActor.throwCustomError(.businessLogicError(code: 500, message: "Test"))
        }
    }
    
    @Test("Error serialization edge cases")
    func errorSerializationEdgeCases() async throws {
        let (client, server) = TestHelpers.makeConnectedPair()
        server.setPreAssignedIDs(["serialization-error-actor"])
        
        let actor = ErrorHandlingActorImpl(actorSystem: server)
        let remoteActor = try $ErrorHandlingActor.resolve(id: actor.id, using: client)
        
        // Test with very long error message
        let longMessage = String(repeating: "Error ", count: 1000)
        let longError = CustomError.businessLogicError(code: 413, message: longMessage)
        
        do {
            try await remoteActor.throwCustomError(longError)
        } catch let error as CustomError {
            guard case .businessLogicError(let code, let message) = error else {
                Issue.record("Expected business logic error")
                return
            }
            #expect(code == 413)
            #expect(message.count == longMessage.count)
        }
        
        // Test with special characters in error
        let specialError = CustomError.validationError(
            field: "json_field",
            reason: "Invalid JSON: {\"test\": \"value with \\\"quotes\\\" and \\n newlines\"}"
        )
        
        do {
            try await remoteActor.throwCustomError(specialError)
        } catch let error as CustomError {
            guard case .validationError(let field, let reason) = error else {
                Issue.record("Expected validation error")
                return
            }
            #expect(field == "json_field")
            #expect(reason.contains("quotes"))
            #expect(reason.contains("newlines"))
        }
    }
}