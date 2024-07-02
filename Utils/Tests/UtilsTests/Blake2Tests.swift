import Foundation
import Testing

@testable import Utils

@Suite struct Blake2Tests {
    @Test func blake2b256Works() throws {
        let testData = Data("test".utf8)
        let expected = Data(
            fromHexString: "928b20366943e2afd11ebc0eae2e53a93bf177a4fcf35bcc64d503704e65e202"
        )
        let actual = try blake2b256(testData)
        #expect(expected == actual.data)
    }
}
