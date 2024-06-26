import XCTest

@testable import Utils

final class Blake2Tests: XCTestCase {
    func testBlake2b256Test() throws {
        let testData = Data("test".utf8)
        let expected = hexStringToData("928b20366943e2afd11ebc0eae2e53a93bf177a4fcf35bcc64d503704e65e202")
        let actual = try blake2b256(testData)
        XCTAssertEqual(expected, actual.data)
    }
}
