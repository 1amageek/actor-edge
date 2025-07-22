import Testing
@testable import ActorEdgeCore

@Suite("Simple Test")
struct SimpleTest {
    @Test("Basic test")
    func basicTest() {
        #expect(1 + 1 == 2)
    }
}