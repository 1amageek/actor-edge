import XCTest

/// Noop test target to prevent `swift test` from failing on the Samples/ directory
final class NoopTests: XCTestCase {
    func testNoop() {
        // This test does nothing and always passes
        XCTAssertTrue(true)
    }
}