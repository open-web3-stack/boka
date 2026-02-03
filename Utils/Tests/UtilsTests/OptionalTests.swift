import Foundation
import Testing
@testable import Utils

struct OptionalTests {
    @Test func unwrapSuccess() throws {
        let optionalValue: Int? = 42

        let result = try optionalValue.unwrap()

        #expect(result == 42)
    }

    @Test func unwrapFailure() throws {
        let optionalValue: Int? = nil

        #expect(throws: OptionalError.nilValue) {
            _ = try optionalValue.unwrap()
        }
    }

    @Test func unwrapOrErrorSuccess() throws {
        let optionalValue: Int? = 42

        let result = try optionalValue.unwrap(orError: NSError(domain: "", code: 1))

        #expect(result == 42)
    }

    @Test func expectSuccess() {
        let optionalValue: Int? = 42

        let result = optionalValue.expect("Value should be present")

        #expect(result == 42)
    }
}
