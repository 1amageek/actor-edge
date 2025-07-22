import Testing
@testable import ActorEdgeCore
import Distributed
import Foundation

@Suite("Result Handler Tests", .tags(.invocation))
struct ResultHandlerTests {
    
    @Test("Handler onReturn with value")
    func handlerOnReturnWithValue() async throws {
        let testMessage = TestMessage(content: "Success result")
        
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: testMessage)
            }
        }
        
        let typedResult = result as! TestMessage
        #expect(typedResult.content == testMessage.content)
    }
    
    @Test("Handler onReturnVoid")
    func handlerOnReturnVoid() async throws {
        let _: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturnVoid()
            }
        }
        
        // Success if we get here without throwing
    }
    
    @Test("Handler onThrow with error")
    func handlerOnThrowWithError() async throws {
        let testError = TestError.errorWithMessage("Test error")
        
        do {
            let _: Any = try await withCheckedThrowingContinuation { continuation in
                let handler = ActorEdgeResultHandler.forLocalReturn(
                    continuation: continuation
                )
                
                Task {
                    try await handler.onThrow(error: testError)
                }
            }
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == testError)
        }
    }
    
    @Test("Remote handler with response writer")
    func remoteHandlerWithResponseWriter() async throws {
        let system = TestHelpers.makeTestActorSystem()
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        // Create a mock response writer
        let writer = InvocationResponseWriter(
            processor: DistributedInvocationProcessor(
                serialization: system.serialization
            ),
            transport: serverTransport,
            recipient: ActorEdgeID("test-client"),
            correlationID: "test-call-123",
            sender: ActorEdgeID("test-server")
        )
        
        let handler = ActorEdgeResultHandler.forRemoteCall(
            system: system,
            callID: "test-call-123",
            responseWriter: writer
        )
        
        // Test onReturn
        let testMessage = TestMessage(content: "Remote result")
        try await handler.onReturn(value: testMessage)
        
        // Verify a response was sent
        var receivedResponse = false
        let receiveTask = Task {
            for await envelope in clientTransport.receive() {
                if envelope.messageType == .response {
                    receivedResponse = true
                    break
                }
            }
        }
        
        // Give some time for the response to be received
        try await Task.sleep(for: .milliseconds(100))
        receiveTask.cancel()
        
        #expect(receivedResponse)
    }
    
    @Test("Remote handler void response")
    func remoteHandlerVoidResponse() async throws {
        let system = TestHelpers.makeTestActorSystem()
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let writer = InvocationResponseWriter(
            processor: DistributedInvocationProcessor(
                serialization: system.serialization
            ),
            transport: serverTransport,
            recipient: ActorEdgeID("test-client"),
            correlationID: "void-call-123",
            sender: ActorEdgeID("test-server")
        )
        
        let handler = ActorEdgeResultHandler.forRemoteCall(
            system: system,
            callID: "void-call-123",
            responseWriter: writer
        )
        
        // Test onReturnVoid
        try await handler.onReturnVoid()
        
        // Verify a void response was sent
        var receivedVoidResponse = false
        let receiveTask = Task {
            for await envelope in clientTransport.receive() {
                if envelope.messageType == .response {
                    receivedVoidResponse = true
                    break
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(100))
        receiveTask.cancel()
        
        #expect(receivedVoidResponse)
    }
    
    @Test("Remote handler error response")
    func remoteHandlerErrorResponse() async throws {
        let system = TestHelpers.makeTestActorSystem()
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let writer = InvocationResponseWriter(
            processor: DistributedInvocationProcessor(
                serialization: system.serialization
            ),
            transport: serverTransport,
            recipient: ActorEdgeID("test-client"),
            correlationID: "error-call-123",
            sender: ActorEdgeID("test-server")
        )
        
        let handler = ActorEdgeResultHandler.forRemoteCall(
            system: system,
            callID: "error-call-123",
            responseWriter: writer
        )
        
        // Test onThrow
        let testError = TestError.errorWithCode(500)
        try await handler.onThrow(error: testError)
        
        // Verify an error response was sent
        var receivedErrorResponse = false
        let receiveTask = Task {
            for await envelope in clientTransport.receive() {
                if envelope.messageType == .error {
                    receivedErrorResponse = true
                    break
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(100))
        receiveTask.cancel()
        
        #expect(receivedErrorResponse)
    }
    
    @Test("Handler with complex return types")
    func handlerComplexReturnTypes() async throws {
        let complexMessage = ComplexTestMessage(
            messages: [TestMessage(content: "nested")],
            metadata: ["key": "value"],
            optional: "present"
        )
        
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: complexMessage)
            }
        }
        
        let typedResult = result as! ComplexTestMessage
        #expect(typedResult.messages.count == 1)
        #expect(typedResult.metadata["key"] == "value")
    }
    
    @Test("Handler with array return type")
    func handlerArrayReturnType() async throws {
        let messages = [
            TestMessage(content: "msg1"),
            TestMessage(content: "msg2"),
            TestMessage(content: "msg3")
        ]
        
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: messages)
            }
        }
        
        let typedResult = result as! [TestMessage]
        #expect(typedResult.count == 3)
        #expect(typedResult[0].content == "msg1")
    }
    
    @Test("Handler with dictionary return type")
    func handlerDictionaryReturnType() async throws {
        let dict = ["one": 1, "two": 2, "three": 3]
        
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: dict)
            }
        }
        
        let typedResult = result as! [String: Int]
        #expect(typedResult.count == 3)
        #expect(typedResult["two"] == 2)
    }
    
    @Test("Handler with optional return type")
    func handlerOptionalReturnType() async throws {
        // Test with Some value
        let someResult: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: Optional("present"))
            }
        }
        let typedSome = someResult as! String?
        #expect(typedSome == "present")
        
        // Test with None value
        let noneResult: Any = try await withCheckedThrowingContinuation { continuation in
            let handler = ActorEdgeResultHandler.forLocalReturn(
                continuation: continuation
            )
            
            Task {
                try await handler.onReturn(value: Optional<String>.none)
            }
        }
        let typedNone = noneResult as! String?
        #expect(typedNone == nil)
    }
    
    @Test("Handler with ActorEdgeError")
    func handlerActorEdgeError() async throws {
        do {
            let _: Any = try await withCheckedThrowingContinuation { continuation in
                let handler = ActorEdgeResultHandler.forLocalReturn(
                    continuation: continuation
                )
                
                Task {
                    try await handler.onThrow(error: ActorEdgeError.timeout)
                }
            }
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
        let (clientTransport, serverTransport) = InMemoryMessageTransport.createConnectedPair()
        
        let writer = InvocationResponseWriter(
            processor: DistributedInvocationProcessor(
                serialization: system.serialization
            ),
            transport: serverTransport,
            recipient: ActorEdgeID("test-client"),
            correlationID: "complex-call",
            sender: ActorEdgeID("test-server")
        )
        
        let handler = ActorEdgeResultHandler.forRemoteCall(
            system: system,
            callID: "complex-call",
            responseWriter: writer
        )
        
        // Test with a complex message that needs serialization
        let complexMessage = ComplexTestMessage(
            messages: (1...5).map { TestMessage(content: "Message \($0)") },
            metadata: ["status": "complete", "version": "1.0"],
            optional: "serialized"
        )
        
        try await handler.onReturn(value: complexMessage)
        
        // Verify the response was sent with proper serialization
        var receivedEnvelope: Envelope?
        let receiveTask = Task {
            for await envelope in clientTransport.receive() {
                if envelope.messageType == .response {
                    receivedEnvelope = envelope
                    break
                }
            }
        }
        
        try await Task.sleep(for: .milliseconds(100))
        receiveTask.cancel()
        
        #expect(receivedEnvelope != nil)
        #expect(receivedEnvelope?.manifest.serializerID == "json")
        #expect(receivedEnvelope?.payload.count ?? 0 > 100) // Complex message should be large
    }
}