import Foundation
@testable import Networking
import Testing

struct QuicMessageTests {
    @Test func receivedMessage() throws {
        let originalMessage = QuicMessage(type: .received, data: Data("received".utf8))
        let encodedData = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(QuicMessage.self, from: encodedData)
        #expect(originalMessage == decodedMessage)
    }

    @Test func shutdownCompleteMessage() throws {
        let originalMessage = QuicMessage(type: .shutdownComplete, data: nil)
        let encodedData = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(QuicMessage.self, from: encodedData)
        #expect(originalMessage == decodedMessage)
    }
}
