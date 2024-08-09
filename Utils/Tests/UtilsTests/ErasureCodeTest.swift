import Foundation
import Testing

@testable import Utils

// somehow without this the GH Actions CI fails
extension Foundation.Bundle: @unchecked @retroactive Sendable {}

@Suite struct ErasureCodeTests {
    @Test func testReconstruct() throws {}
}
