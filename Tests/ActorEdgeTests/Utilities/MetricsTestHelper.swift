import Foundation
import Metrics
import Testing

/// Test metrics factory for validating metrics behavior
public final class TestMetrics: MetricsFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var counters: [String: TestCounter] = [:]
    private var timers: [String: TestTimer] = [:]

    public init() {}

    public func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        lock.lock()
        defer { lock.unlock() }

        let key = Self.makeKey(label: label, dimensions: dimensions)
        if let existing = counters[key] {
            return existing
        }

        let counter = TestCounter(label: label, dimensions: dimensions)
        counters[key] = counter
        return counter
    }

    public func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> any RecorderHandler {
        lock.lock()
        defer { lock.unlock() }

        let key = Self.makeKey(label: label, dimensions: dimensions)
        if let existing = timers[key] {
            return existing
        }

        let timer = TestTimer(label: label, dimensions: dimensions)
        timers[key] = timer
        return timer
    }

    public func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        lock.lock()
        defer { lock.unlock() }

        let key = Self.makeKey(label: label, dimensions: dimensions)
        if let existing = timers[key] {
            return existing
        }

        let timer = TestTimer(label: label, dimensions: dimensions)
        timers[key] = timer
        return timer
    }

    public func destroyCounter(_ handler: any CounterHandler) {
        if let counter = handler as? TestCounter {
            lock.lock()
            defer { lock.unlock() }
            counters.removeValue(forKey: counter.key)
        }
    }

    public func destroyRecorder(_ handler: any RecorderHandler) {
        if let timer = handler as? TestTimer {
            lock.lock()
            defer { lock.unlock() }
            timers.removeValue(forKey: timer.key)
        }
    }

    public func destroyTimer(_ handler: TimerHandler) {
        if let timer = handler as? TestTimer {
            lock.lock()
            defer { lock.unlock() }
            timers.removeValue(forKey: timer.key)
        }
    }

    static func makeKey(label: String, dimensions: [(String, String)]) -> String {
        let dimensionsString = dimensions
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: ",")
        return "\(label)[\(dimensionsString)]"
    }

    // MARK: - Test Helpers

    public func getCounter(label: String, dimensions: [(String, String)] = []) -> TestCounter? {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.makeKey(label: label, dimensions: dimensions)
        return counters[key]
    }

    public func getTimer(label: String, dimensions: [(String, String)] = []) -> TestTimer? {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.makeKey(label: label, dimensions: dimensions)
        return timers[key]
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        counters.removeAll()
        timers.removeAll()
    }
}

// MARK: - Test Handlers

public final class TestCounter: CounterHandler, @unchecked Sendable {
    let label: String
    let dimensions: [(String, String)]
    let key: String

    private let lock = NSLock()
    private var _value: Int64 = 0

    public var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    init(label: String, dimensions: [(String, String)]) {
        self.label = label
        self.dimensions = dimensions
        self.key = TestMetrics.makeKey(label: label, dimensions: dimensions)
    }

    public func increment(by amount: Int64) {
        lock.lock()
        defer { lock.unlock() }
        _value += amount
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _value = 0
    }
}

public final class TestTimer: RecorderHandler, TimerHandler, @unchecked Sendable {
    let label: String
    let dimensions: [(String, String)]
    let key: String

    private let lock = NSLock()
    private var _values: [Double] = []

    public var values: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _values.count
    }

    init(label: String, dimensions: [(String, String)]) {
        self.label = label
        self.dimensions = dimensions
        self.key = TestMetrics.makeKey(label: label, dimensions: dimensions)
    }

    public func record(_ value: Int64) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(Double(value))
    }

    public func record(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(value)
    }

    public func recordNanoseconds(_ duration: Int64) {
        lock.lock()
        defer { lock.unlock() }
        _values.append(Double(duration) / 1_000_000_000.0)
    }
}

// MARK: - Assertion Helpers

extension TestCounter {
    public func assertValue(_ expected: Int64, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(value == expected, "Counter '\(label)' expected \(expected), got \(value)", sourceLocation: sourceLocation)
    }

    public func assertIncremented(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(value > 0, "Counter '\(label)' was not incremented", sourceLocation: sourceLocation)
    }
}

extension TestTimer {
    public func assertRecorded(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(count > 0, "Timer '\(label)' has no recordings", sourceLocation: sourceLocation)
    }

    public func assertCount(_ expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(count == expected, "Timer '\(label)' expected \(expected) recordings, got \(count)", sourceLocation: sourceLocation)
    }
}
