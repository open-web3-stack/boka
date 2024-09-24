import Foundation
@testable import Networking
import Testing

struct QuicMessageTests {
    @Test func testEncodingAndDecodingUnknownMessage() throws {
        let originalMessage = QuicMessage(type: .unknown, data: nil)
        let encodedData = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(QuicMessage.self, from: encodedData)
        #expect(originalMessage == decodedMessage)
    }

    @Test func testEncodingAndDecodingReceivedMessage() throws {
        let originalMessage = QuicMessage(type: .received, data: Data("received".utf8))
        let encodedData = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(QuicMessage.self, from: encodedData)
        #expect(originalMessage == decodedMessage)
    }

    @Test func testEncodingAndDecodingShutdownCompleteMessage() throws {
        let originalMessage = QuicMessage(type: .shutdownComplete, data: nil)
        let encodedData = try JSONEncoder().encode(originalMessage)
        let decodedMessage = try JSONDecoder().decode(QuicMessage.self, from: encodedData)
        #expect(originalMessage == decodedMessage)
    }
}
