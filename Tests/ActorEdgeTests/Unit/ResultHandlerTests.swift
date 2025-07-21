import Testing
@testable import ActorEdgeCore
import Distributed

@Suite("Result Handler Tests", .tags(.invocation))
struct ResultHandlerTests {
    
    @Test("Handler onReturn with value")
    func handlerOnReturnWithValue() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create a test continuation
        let expectation = AsyncExpectation<TestMessage>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        let testMessage = TestMessage(content: "Success result")
        try await handler.onReturn(value: testMessage)
        
        let result = await expectation.value
        #expect(result.content == testMessage.content)
    }
    
    @Test("Handler onReturnVoid")
    func handlerOnReturnVoid() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create a void continuation
        let expectation = AsyncExpectation<Void>()
        
        let handler = ActorEdgeResultHandler(
            voidContinuation: expectation.continuation,
            system: system
        )
        
        try await handler.onReturnVoid()
        
        // Should complete without error
        _ = await expectation.value
    }
    
    @Test("Handler onThrow with error")
    func handlerOnThrowWithError() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create a test continuation
        let expectation = AsyncExpectation<TestMessage>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        let testError = TestError.errorWithMessage("Test error")
        try await handler.onThrow(error: testError)
        
        do {
            _ = await expectation.value
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == testError)
        }
    }
    
    @Test("Remote handler with response writer")
    func remoteHandlerWithResponseWriter() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Create mock response writer
        let writer = MockResponseWriter()
        
        let handler = ActorEdgeResultHandler(
            responseWriter: writer,
            system: system
        )
        
        // Test onReturn
        let testMessage = TestMessage(content: "Remote result")
        try await handler.onReturn(value: testMessage)
        
        #expect(writer.writtenData != nil)
        #expect(writer.writtenData?.count ?? 0 > 0)
        #expect(writer.isSuccess == true)
    }
    
    @Test("Remote handler void response")
    func remoteHandlerVoidResponse() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let writer = MockResponseWriter()
        
        let handler = ActorEdgeResultHandler(
            responseWriter: writer,
            system: system
        )
        
        // Test onReturnVoid
        try await handler.onReturnVoid()
        
        #expect(writer.writtenData != nil)
        #expect(writer.isSuccess == true)
    }
    
    @Test("Remote handler error response")
    func remoteHandlerErrorResponse() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let writer = MockResponseWriter()
        
        let handler = ActorEdgeResultHandler(
            responseWriter: writer,
            system: system
        )
        
        // Test onThrow
        let testError = TestError.errorWithCode(500)
        try await handler.onThrow(error: testError)
        
        #expect(writer.writtenData != nil)
        #expect(writer.isSuccess == false)
        #expect(writer.errorType != nil)
    }
    
    @Test("Handler with complex return types")
    func handlerComplexReturnTypes() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let expectation = AsyncExpectation<ComplexTestMessage>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        let complexMessage = ComplexTestMessage(
            messages: [TestMessage(content: "nested")],
            metadata: ["key": "value"],
            optional: "present"
        )
        
        try await handler.onReturn(value: complexMessage)
        
        let result = await expectation.value
        #expect(result.messages.count == 1)
        #expect(result.metadata["key"] == "value")
    }
    
    @Test("Handler with array return type")
    func handlerArrayReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let expectation = AsyncExpectation<[TestMessage]>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        let messages = [
            TestMessage(content: "msg1"),
            TestMessage(content: "msg2"),
            TestMessage(content: "msg3")
        ]
        
        try await handler.onReturn(value: messages)
        
        let result = await expectation.value
        #expect(result.count == 3)
        #expect(result[0].content == "msg1")
    }
    
    @Test("Handler with dictionary return type")
    func handlerDictionaryReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let expectation = AsyncExpectation<[String: Int]>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        let dict = ["one": 1, "two": 2, "three": 3]
        
        try await handler.onReturn(value: dict)
        
        let result = await expectation.value
        #expect(result.count == 3)
        #expect(result["two"] == 2)
    }
    
    @Test("Handler with optional return type")
    func handlerOptionalReturnType() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        // Test with Some value
        let someExpectation = AsyncExpectation<String?>()
        let someHandler = ActorEdgeResultHandler(
            continuation: someExpectation.continuation,
            system: system
        )
        
        try await someHandler.onReturn(value: Optional("present"))
        let someResult = await someExpectation.value
        #expect(someResult == "present")
        
        // Test with None value
        let noneExpectation = AsyncExpectation<String?>()
        let noneHandler = ActorEdgeResultHandler(
            continuation: noneExpectation.continuation,
            system: system
        )
        
        try await noneHandler.onReturn(value: Optional<String>.none)
        let noneResult = await noneExpectation.value
        #expect(noneResult == nil)
    }
    
    @Test("Handler with ActorEdgeError")
    func handlerActorEdgeError() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let expectation = AsyncExpectation<TestMessage>()
        
        let handler = ActorEdgeResultHandler(
            continuation: expectation.continuation,
            system: system
        )
        
        try await handler.onThrow(error: ActorEdgeError.timeout)
        
        do {
            _ = await expectation.value
            Issue.record("Expected ActorEdgeError.timeout")
        } catch ActorEdgeError.timeout {
            // Expected
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    @Test("Handler serialization for remote response")
    func handlerSerializationForRemoteResponse() async throws {
        let system = TestHelpers.makeTestActorSystem()
        
        let writer = MockResponseWriter()
        let handler = ActorEdgeResultHandler(
            responseWriter: writer,
            system: system
        )
        
        // Test with a complex message that needs serialization
        let complexMessage = ComplexTestMessage(
            messages: (1...5).map { TestMessage(content: "Message \($0)") },
            metadata: ["status": "complete", "version": "1.0"],
            optional: "serialized"
        )
        
        try await handler.onReturn(value: complexMessage)
        
        #expect(writer.writtenData != nil)
        #expect(writer.writtenData?.count ?? 0 > 100) // Complex message should be large
        #expect(writer.manifest?.serializerID == "json")
    }
}

// MARK: - Test Helpers

/// Async expectation helper for testing continuations
private actor AsyncExpectation<T> {
    private var result: Result<T, Error>?
    private var waiters: [CheckedContinuation<T, Error>] = []
    
    var continuation: CheckedContinuation<T, Error> {
        get async {
            await withCheckedContinuation { continuation in
                Task {
                    await self.setContinuation(continuation)
                }
            }
        }
    }
    
    private func setContinuation(_ continuation: CheckedContinuation<T, Error>) {
        if let result = result {
            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        } else {
            waiters.append(continuation)
        }
    }
    
    func fulfill(with value: T) {
        result = .success(value)
        for waiter in waiters {
            waiter.resume(returning: value)
        }
        waiters.removeAll()
    }
    
    func reject(with error: Error) {
        result = .failure(error)
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
        waiters.removeAll()
    }
    
    var value: T {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.getValue(continuation: continuation)
                }
            }
        }
    }
    
    private func getValue(continuation: CheckedContinuation<T, Error>) {
        if let result = result {
            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        } else {
            waiters.append(continuation)
        }
    }
}

extension ActorEdgeResultHandler {
    /// Convenience initializer for testing with continuation
    init<T>(continuation: CheckedContinuation<T, Error>, system: ActorEdgeSystem) {
        self.init(
            continuation: { value in
                continuation.resume(returning: value)
            },
            errorContinuation: { error in
                continuation.resume(throwing: error)
            },
            system: system
        )
    }
    
    /// Convenience initializer for testing with void continuation
    init(voidContinuation: CheckedContinuation<Void, Error>, system: ActorEdgeSystem) {
        self.init(
            voidContinuation: {
                voidContinuation.resume(returning: ())
            },
            errorContinuation: { error in
                voidContinuation.resume(throwing: error)
            },
            system: system
        )
    }
    
    /// Convenience initializer for testing with response writer
    init(responseWriter: MockResponseWriter, system: ActorEdgeSystem) {
        self.init(
            responseWriter: { data, manifest, isError, errorType in
                responseWriter.write(data: data, manifest: manifest, isError: isError, errorType: errorType)
            },
            system: system
        )
    }
}

/// Mock response writer for testing
private final class MockResponseWriter: @unchecked Sendable {
    private(set) var writtenData: Data?
    private(set) var manifest: SerializationManifest?
    private(set) var isSuccess: Bool = false
    private(set) var errorType: String?
    
    func write(data: Data, manifest: SerializationManifest, isError: Bool, errorType: String?) {
        self.writtenData = data
        self.manifest = manifest
        self.isSuccess = !isError
        self.errorType = errorType
    }
}