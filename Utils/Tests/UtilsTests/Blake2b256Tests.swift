import Foundation
import Testing

@testable import Utils

@Suite struct Blake2b256Tests {
    @Test func works() throws {
        let testData = Data("test".utf8)
        let expected = Data(
            fromHexString: "928b20366943e2afd11ebc0eae2e53a93bf177a4fcf35bcc64d503704e65e202"
        )
        let actual = testData.hash(using: Blake2b256.self)
        #expect(expected == actual.data)
    }
}
