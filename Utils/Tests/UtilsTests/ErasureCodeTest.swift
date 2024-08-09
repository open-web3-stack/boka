import Foundation

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

@testable import Utils

@Suite struct ErasureCodeTests {
    @Test func testReconstruct() throws {}
}
