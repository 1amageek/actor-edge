import Foundation
import NIOCore
import NIOConcurrencyHelpers
import Logging
import Metrics

/// Call ID type for distributed calls
public typealias CallID = String

/// Manages in-flight remote calls using EventLoopPromise
/// Hybrid pattern: NIO EventLoopPromise + Swift async/await bridging
public final class CallLifecycleManager: @unchecked Sendable {
    
    /// Manager state
    public enum State: Sendable, Equatable {
        case running
        case draining
        case terminated
    }
    
    /// In-flight call information
    private struct InFlightCall {
        let promise: EventLoopPromise<ByteBuffer>
        let timeoutTask: Scheduled<Void>
        let startTime: DispatchTime
    }
    
    // Dependencies
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    
    // Metrics
    private let inflightGauge: Gauge
    private let timeoutCounter: Counter
    private let latencyTimer: Timer
    private let drainTimer: Timer
    private let metricNames: MetricNames
    
    // Track in-flight count separately for Gauge
    private var inflightCount: Int = 0
    
    // State management
    private var calls: [CallID: InFlightCall] = [:]
    private let lock = NIOLock()
    
    // State stream
    private let stateStream: AsyncStream<State>
    private let stateContinuation: AsyncStream<State>.Continuation
    
    // Current state
    private(set) var state: State = .running {
        didSet {
            if oldValue != state {
                stateContinuation.yield(state)
            }
        }
    }
    
    public init(eventLoopGroup: EventLoopGroup, metricsNamespace: String = "actor_edge") {
        self.eventLoopGroup = eventLoopGroup
        self.logger = Logger(label: "ActorEdge.CallLifecycle")
        
        // Initialize metrics
        self.metricNames = MetricNames(namespace: metricsNamespace)
        self.inflightGauge = Gauge(label: metricNames.inflightCalls)
        self.timeoutCounter = Counter(label: metricNames.callsTimedOutTotal)
        self.latencyTimer = Timer(label: metricNames.callLatencySeconds)
        self.drainTimer = Timer(label: metricNames.drainDurationSeconds)
        
        // Create state stream
        let (stream, continuation) = AsyncStream<State>.makeStream()
        self.stateStream = stream
        self.stateContinuation = continuation
        
        // Yield initial state
        continuation.yield(.running)
    }
    
    // MARK: - Public API
    
    /// State change notifications
    public var states: AsyncStream<State> {
        stateStream
    }
    
    /// Current number of in-flight calls
    public var inFlightCount: Int {
        lock.withLock { inflightCount }
    }
    
    /// Register a new call and return a future for its response
    public func register(
        callID: CallID,
        eventLoop: EventLoop,
        timeout: TimeAmount
    ) throws -> EventLoopFuture<ByteBuffer> {
        // Check state
        let currentState = lock.withLock { state }
        guard currentState == .running else {
            throw ActorEdgeError.systemShutDown
        }
        
        // Verify EventLoop (simplified check)
        assert(eventLoop.inEventLoop || Thread.isMainThread,
               "register() must be called from the specified EventLoop")
        
        // Create promise
        let promise = eventLoop.makePromise(of: ByteBuffer.self)
        
        // Schedule timeout task
        let timeoutTask: Scheduled<Void> = eventLoop.scheduleTask(in: timeout) { [weak self] in
            self?.timeout(callID: callID)
        }
        
        let call = InFlightCall(
            promise: promise,
            timeoutTask: timeoutTask,
            startTime: DispatchTime.now()
        )
        
        lock.withLock {
            calls[callID] = call
            inflightCount += 1
        }
        
        // Update metrics
        inflightGauge.record(Double(inflightCount))
        
        logger.trace("Registered call", metadata: [
            "callID": "\(callID)",
            "timeout": "\(timeout)"
        ])
        
        return promise.futureResult
    }
    
    /// Complete a call successfully with response data
    public func succeed(callID: CallID, buffer: ByteBuffer) {
        let startTime = lock.withLock { calls[callID]?.startTime }
        
        complete(callID) { promise in
            promise.succeed(buffer)
        }
        
        // Record latency if we have start time
        if let startTime = startTime {
            let duration = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
            latencyTimer.recordNanoseconds(Int64(duration))
        }
    }
    
    /// Fail a call with an error
    public func fail(callID: CallID, error: Error) {
        complete(callID) { promise in
            promise.fail(error)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Common completion logic
    private func complete(_ callID: CallID, _ operation: (EventLoopPromise<ByteBuffer>) -> Void) {
        guard let call = lock.withLock({ calls.removeValue(forKey: callID) }) else {
            logger.warning("Late completion for unknown call", metadata: [
                "callID": "\(callID)"
            ])
            return
        }
        
        // Cancel timeout
        call.timeoutTask.cancel()
        
        // Execute operation
        operation(call.promise)
        
        // Update metrics
        lock.withLock {
            inflightCount = max(0, inflightCount - 1)
        }
        inflightGauge.record(Double(inflightCount))
        
        // Check if draining and no more calls
        lock.withLock {
            if calls.isEmpty && state == .draining {
                // Signal drain completion with empty yield
                stateContinuation.yield(state)
            }
        }
        
        logger.trace("Call completed", metadata: [
            "callID": "\(callID)"
        ])
    }
    
    /// Handle timeout
    private func timeout(callID: CallID) {
        logger.debug("Call timed out", metadata: [
            "callID": "\(callID)"
        ])
        
        // Update metrics
        timeoutCounter.increment()
        
        fail(callID: callID, error: ActorEdgeError.timeout)
    }
    
    // MARK: - Shutdown Management
    
    /// Cancel all pending calls with a specific error
    public func cancelAll(_ reason: ActorEdgeError = .systemShutDown) {
        let allCalls = lock.withLock {
            let calls = self.calls
            self.calls.removeAll()
            return calls
        }
        
        logger.info("Cancelling all pending calls", metadata: [
            "count": "\(allCalls.count)",
            "reason": "\(reason)"
        ])
        
        for (_, call) in allCalls {
            // Cancel timeout
            call.timeoutTask.cancel()
            
            // Fail the promise
            call.promise.fail(reason)
        }
    }
    
    /// Drain calls until deadline or all complete
    public func drain(until deadline: NIODeadline) async {
        let drainStart = DispatchTime.now()
        
        // Transition to draining
        lock.withLock {
            guard state == .running else { return }
            state = .draining
        }
        
        // Check if already empty
        let hasInFlight = await withCheckedContinuation { continuation in
            lock.withLock {
                continuation.resume(returning: !calls.isEmpty)
            }
        }
        
        if !hasInFlight {
            terminate()
            return
        }
        
        // Wait for either all calls to complete or deadline
        let doneTask = Task {
            // Wait for empty signal (yielded in complete())
            for await _ in stateStream {
                break
            }
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(deadline.uptimeNanoseconds - NIODeadline.now().uptimeNanoseconds))
        }
        
        // Wait for either completion
        await withTaskCancellationHandler {
            async let _ = doneTask.value
            async let _ = timeoutTask.value
            _ = await (try? timeoutTask.value)
        } onCancel: {
            // No-op, tasks will be cancelled
        }
        
        // Cancel remaining tasks
        timeoutTask.cancel()
        doneTask.cancel()
        
        // Terminate
        terminate()
        
        // Record drain duration
        let drainDuration = DispatchTime.now().uptimeNanoseconds - drainStart.uptimeNanoseconds
        drainTimer.recordNanoseconds(Int64(drainDuration))
    }
    
    /// Terminate the manager
    private func terminate() {
        cancelAll()
        lock.withLock {
            state = .terminated
        }
        stateContinuation.finish()
    }
}

// MARK: - ActorEdgeError Extension

extension ActorEdgeError {
    /// System is shutting down
    public static let systemShutDown = ActorEdgeError.transportError("System shutting down")
}

