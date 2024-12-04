import Foundation
import Testing

@testable import Utils

struct OptionalTests {
    @Test func testUnwrapSuccess() throws {
        let optionalValue: Int? = 42

        let result = try optionalValue.unwrap()

        #expect(result == 42)
    }

    @Test func testUnwrapFailure() throws {
        let optionalValue: Int? = nil

        #expect(throws: OptionalError.nilValue) {
            _ = try optionalValue.unwrap()
        }
    }

    @Test func testUnwrapOrErrorSuccess() throws {
        let optionalValue: Int? = 42

        let result = try optionalValue.unwrap(orError: NSError(domain: "", code: 1))

        #expect(result == 42)
    }

    @Test func testExpectSuccess() throws {
        let optionalValue: Int? = 42

        let result = optionalValue.expect("Value should be present")

        #expect(result == 42)
    }
}
