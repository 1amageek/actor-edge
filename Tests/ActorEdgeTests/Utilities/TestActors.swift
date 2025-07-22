import Testing
import Foundation
@testable import ActorEdgeCore
import Distributed

// MARK: - Test Message Types

/// Test message types
public struct TestMessage: Codable, Sendable, Equatable {
    public let id: String
    public let content: String
    public let timestamp: Date
    
    public init(id: String = UUID().uuidString, content: String, timestamp: Date = Date()) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
    }
    
    @_optimize(none)
    public static func _forceTypeRetention() {
        _ = TestMessage.self
        _ = String(reflecting: TestMessage.self)
    }
}

public struct ComplexMessage: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let numbers: [Int]
    public let nested: NestedData
    public let optional: String?
    
    public struct NestedData: Codable, Sendable, Equatable {
        public let flag: Bool
        public let values: [String: Double]
        
        public init(flag: Bool, values: [String: Double]) {
            self.flag = flag
            self.values = values
        }
    }
    
    public init(
        timestamp: Date = Date(),
        numbers: [Int] = [1, 2, 3, 4, 5],
        nested: NestedData = NestedData(flag: true, values: ["pi": 3.14159, "e": 2.71828]),
        optional: String? = "optional_value"
    ) {
        self.timestamp = timestamp
        self.numbers = numbers
        self.nested = nested
        self.optional = optional
    }
    
    @_optimize(none)
    public static func _forceTypeRetention() {
        _ = ComplexMessage.self
        _ = String(reflecting: ComplexMessage.self)
    }
}

/// Complex test message for advanced testing
public struct ComplexTestMessage: Codable, Sendable, Equatable {
    public let messages: [TestMessage]
    public let metadata: [String: String]
    public let optional: String?
    public let numbers: [Int]
    public let nested: NestedData
    
    public struct NestedData: Codable, Sendable, Equatable {
        public let flag: Bool
        public let values: [String: Double]
        
        public init(flag: Bool = true, values: [String: Double] = [:]) {
            self.flag = flag
            self.values = values
        }
    }
    
    public init(
        messages: [TestMessage] = [],
        metadata: [String: String] = [:],
        optional: String? = nil,
        numbers: [Int] = [],
        nested: NestedData = NestedData()
    ) {
        self.messages = messages
        self.metadata = metadata
        self.optional = optional
        self.numbers = numbers
        self.nested = nested
    }
    
    @_optimize(none)
    public static func _forceTypeRetention() {
        _ = ComplexTestMessage.self
        _ = String(reflecting: ComplexTestMessage.self)
    }
}

// MARK: - Test Error Types

/// Test error types
public enum TestError: Error, Codable, Sendable, Equatable {
    case simpleError
    case errorWithMessage(String)
    case errorWithCode(Int)
    case networkError
    case timeoutError
    case validationError(field: String, message: String)
    
    @_optimize(none)
    public static func _forceTypeRetention() {
        _ = TestError.self
        _ = String(reflecting: TestError.self)
    }
}

// MARK: - Test Actor Protocols and Implementations

/// Main test actor protocol
@Resolvable
public protocol TestActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func echo(_ message: TestMessage) async throws -> TestMessage
    distributed func process(_ messages: [TestMessage]) async throws -> [TestMessage]
    distributed func complexOperation(_ data: ComplexMessage) async throws -> ComplexMessage
    distributed func throwsError() async throws
    distributed func throwsSpecificError(_ error: TestError) async throws
    distributed func voidMethod() async throws
    distributed func getCounter() async throws -> Int
    distributed func incrementCounter() async throws -> Int
}

/// Test actor implementation
public distributed actor TestActorImpl: TestActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    private var counter: Int = 0
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func echo(_ message: TestMessage) async throws -> TestMessage {
        return message
    }
    
    public distributed func process(_ messages: [TestMessage]) async throws -> [TestMessage] {
        return messages.map { 
            TestMessage(
                id: "\($0.id)_processed",
                content: "Processed: \($0.content)",
                timestamp: Date()
            )
        }
    }
    
    public distributed func complexOperation(_ data: ComplexMessage) async throws -> ComplexMessage {
        return ComplexMessage(
            timestamp: Date(),
            numbers: data.numbers.map { $0 * 2 },
            nested: ComplexMessage.NestedData(
                flag: !data.nested.flag,
                values: data.nested.values.mapValues { $0 * 2 }
            ),
            optional: data.optional?.uppercased()
        )
    }
    
    public distributed func throwsError() async throws {
        throw ActorEdgeError.timeout
    }
    
    public distributed func throwsSpecificError(_ error: TestError) async throws {
        throw error
    }
    
    public distributed func voidMethod() async throws {
        counter += 1
    }
    
    public distributed func getCounter() async throws -> Int {
        return counter
    }
    
    public distributed func incrementCounter() async throws -> Int {
        counter += 1
        return counter
    }
}

/// Simple echo actor for basic tests
@Resolvable
public protocol EchoActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func echo<T: Codable & Sendable>(_ value: T) async throws -> T
    distributed func echoString(_ string: String) async throws -> String
    distributed func echoArray(_ array: [String]) async throws -> [String]
}

public distributed actor EchoActorImpl: EchoActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func echo<T: Codable & Sendable>(_ value: T) async throws -> T {
        return value
    }
    
    public distributed func echoString(_ string: String) async throws -> String {
        return string
    }
    
    public distributed func echoArray(_ array: [String]) async throws -> [String] {
        return array
    }
}

/// State management actor for concurrency tests
@Resolvable
public protocol StatefulActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func setState(_ key: String, value: String) async throws
    distributed func getState(_ key: String) async throws -> String?
    distributed func getAccessCount() async throws -> Int
    distributed func clearState() async throws
}

public distributed actor StatefulActorImpl: StatefulActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    private var state: [String: String] = [:]
    private var accessCount: Int = 0
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func setState(_ key: String, value: String) async throws {
        state[key] = value
        accessCount += 1
    }
    
    public distributed func getState(_ key: String) async throws -> String? {
        accessCount += 1
        return state[key]
    }
    
    public distributed func getAccessCount() async throws -> Int {
        return accessCount
    }
    
    public distributed func clearState() async throws {
        state.removeAll()
        accessCount = 0
    }
}

/// Counting actor for simple state tests
@Resolvable
public protocol CountingActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func increment() async throws
    distributed func decrement() async throws
    distributed func getCount() async throws -> Int
    distributed func reset() async throws
}

public distributed actor CountingActorImpl: CountingActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    private var count = 0
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func increment() async throws {
        count += 1
    }
    
    public distributed func decrement() async throws {
        count -= 1
    }
    
    public distributed func getCount() async throws -> Int {
        return count
    }
    
    public distributed func reset() async throws {
        count = 0
    }
}

/// Slow actor for timeout and performance tests
@Resolvable
public protocol SlowActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func slowOperation(delaySeconds: Int) async throws -> String
    distributed func slowEcho(_ message: String, delayMS: Int) async throws -> String
}

public distributed actor SlowActorImpl: SlowActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func slowOperation(delaySeconds: Int) async throws -> String {
        try await Task.sleep(for: .seconds(delaySeconds))
        return "Completed after \(delaySeconds) seconds"
    }
    
    public distributed func slowEcho(_ message: String, delayMS: Int) async throws -> String {
        try await Task.sleep(for: .milliseconds(delayMS))
        return message
    }
}

/// Complex actor for advanced testing scenarios
@Resolvable
public protocol ComplexTestActor: DistributedActor where ActorSystem == ActorEdgeSystem {
    distributed func processComplex(_ message: ComplexMessage) async throws -> ComplexMessage
    distributed func batchProcess(_ messages: [TestMessage]) async throws -> [TestMessage]
    distributed func streamProcess(_ count: Int) async throws -> [TestMessage]
}

public distributed actor ComplexTestActorImpl: ComplexTestActor {
    public typealias ActorSystem = ActorEdgeSystem
    
    public init(actorSystem: ActorSystem) {
        self.actorSystem = actorSystem
    }
    
    public distributed func processComplex(_ message: ComplexMessage) async throws -> ComplexMessage {
        var processed = message
        // Add a processing marker
        var newValues = processed.nested.values
        newValues["processed"] = 1.0
        
        return ComplexMessage(
            timestamp: Date(),
            numbers: processed.numbers + [999], // Add marker number
            nested: ComplexMessage.NestedData(
                flag: !processed.nested.flag,
                values: newValues
            ),
            optional: processed.optional.map { "Processed: \($0)" }
        )
    }
    
    public distributed func batchProcess(_ messages: [TestMessage]) async throws -> [TestMessage] {
        return try await withThrowingTaskGroup(of: TestMessage.self) { group in
            for message in messages {
                group.addTask {
                    // Simulate some async processing
                    try await Task.sleep(for: .milliseconds(10))
                    return TestMessage(
                        id: message.id,
                        content: "Batch: \(message.content)",
                        timestamp: Date()
                    )
                }
            }
            
            var results: [TestMessage] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    public distributed func streamProcess(_ count: Int) async throws -> [TestMessage] {
        var messages: [TestMessage] = []
        for i in 0..<count {
            try await Task.sleep(for: .milliseconds(5))
            messages.append(TestMessage(
                id: "stream-\(i)",
                content: "Stream message \(i)",
                timestamp: Date()
            ))
        }
        return messages
    }
}