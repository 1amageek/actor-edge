import Testing
import Foundation

@Suite("Basic Swift Testing Verification")
struct BasicTests {
    
    @Test("Basic expectation test")
    func testBasicExpectation() async throws {
        #expect(true)
        #expect(1 + 1 == 2)
        #expect("hello".count == 5)
    }
    
    @Test("Async test functionality")
    func testAsyncFunctionality() async throws {
        let result = await withCheckedContinuation { continuation in
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                continuation.resume(returning: "success")
            }
        }
        #expect(result == "success")
    }
    
    @Test("Error handling test")
    func testErrorHandling() async throws {
        enum TestError: Error {
            case testCase
        }
        
        do {
            throw TestError.testCase
        } catch {
            #expect(error is TestError)
        }
    }
}