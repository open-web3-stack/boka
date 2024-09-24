import Foundation
@testable import Networking
import Testing

struct QuicErrorTests {
    @Test func testEncodingAndDecodingInvalidStatus() throws {
        let originalError = QuicError.invalidStatus(
            status: QuicStatusCode.internalError
        )
        let encodedData = try JSONEncoder().encode(originalError)
        let decodedError = try JSONDecoder().decode(QuicError.self, from: encodedData)
        #expect(originalError == decodedError)
    }

    @Test func testEncodingAndDecodingGetApiFailed() throws {
        let originalError = QuicError.getApiFailed
        let encodedData = try JSONEncoder().encode(originalError)
        let decodedError = try JSONDecoder().decode(QuicError.self, from: encodedData)
        #expect(originalError == decodedError)
    }

    @Test func testEncodingAndDecodingMessageNotFound() throws {
        let originalError = QuicError.messageNotFound
        let encodedData = try JSONEncoder().encode(originalError)
        let decodedError = try JSONDecoder().decode(QuicError.self, from: encodedData)
        #expect(originalError == decodedError)
    }

    @Test func testEncodingAndDecodingSendFailed() throws {
        let originalError = QuicError.sendFailed
        let encodedData = try JSONEncoder().encode(originalError)
        let decodedError = try JSONDecoder().decode(QuicError.self, from: encodedData)
        #expect(originalError == decodedError)
    }
}
