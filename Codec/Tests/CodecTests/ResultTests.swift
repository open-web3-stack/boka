import Foundation
import Testing

@testable import Codec

struct ResultCodingTests {
    enum ResultError: Error, Codable, Equatable {
        case unknownError(String)
    }

    enum MyResult<Success: Codable & Equatable>: Codable, Equatable {
        case success(Success)
        case failure(ResultError)

        private enum CodingKeys: String, CodingKey {
            case success, failure
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let value = try container.decode(Success.self, forKey: .success)
            self = .success(value)
        }

        // Encodable implementation
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .success(value):
                try container.encode(value, forKey: .success)
            case let .failure(error):
                try container.encode(error, forKey: .failure)
            }
        }
    }

    struct TestStruct: Codable, Equatable {
        let name: String
    }

    @Test func structTests() throws {
        let successResult: MyResult<TestStruct> = .success(TestStruct(name: "Success"))
        let failureResult: MyResult<TestStruct> = .failure(.unknownError("Test Error"))

        let encodedSuccess = try JamEncoder.encode(successResult)
        let encodedFailure = try JamEncoder.encode(failureResult)

        let decodedSuccess = try JamDecoder.decode(MyResult<TestStruct>.self, from: encodedSuccess)
        let decodedFailure = try JamDecoder.decode(MyResult<TestStruct>.self, from: encodedFailure)

        #expect(decodedSuccess == successResult)
        #expect(decodedFailure == decodedFailure)
    }

    @Test func result() throws {
        let successResult: MyResult<String> = .success("Success!")
        let failureResult: MyResult<String> = .failure(.unknownError("An unknown error occurred"))

        let encodedSuccess = try JamEncoder.encode(successResult)
        let encodedFailure = try JamEncoder.encode(failureResult)

        let decodedSuccess = try JamDecoder.decode(MyResult<String>.self, from: encodedSuccess)
        let decodedFailure = try JamDecoder.decode(MyResult<String>.self, from: encodedFailure)

        #expect(decodedSuccess == successResult)
        #expect(decodedFailure == decodedFailure)
    }

    @Test func variant() throws {
        // Invalid variant value (e.g. value 2)
        let invalidData = Data([0x02] + "Invalid variant".utf8)

        // Expect decoding to fail and return nil
        #expect(throws: Error.self) {
            _ = try JamDecoder.decode(Result<String, ResultError>.self, from: invalidData)
        }
    }
}
