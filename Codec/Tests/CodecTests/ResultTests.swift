import Foundation
import Testing

@testable import Codec

struct ResultCodingTests {
    enum ResultError: Error, Codable {
        case unknownError(String)
    }

    enum MyResult<Success: Codable>: Codable {
        case success(Success)
        case failure(ResultError)

        private enum CodingKeys: String, CodingKey {
            case success, failure
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.success) {
                let value = try container.decode(Success.self, forKey: .success)
                self = .success(value)
            } else if container.contains(.failure) {
                let error = try container.decode(ResultError.self, forKey: .failure)
                self = .failure(error)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .failure, in: container, debugDescription: "Invalid data format")
            }
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

        #expect(decodedFailure != nil)
        #expect(decodedSuccess != nil)
    }

    @Test func result() throws {
        let successResult: MyResult<String> = .success("Success!")
        let failureResult: MyResult<String> = .failure(.unknownError("An unknown error occurred"))

        let encodedSuccess = try JamEncoder.encode(successResult)
        let encodedFailure = try JamEncoder.encode(failureResult)

        let decodedSuccess = try JamDecoder.decode(MyResult<String>.self, from: encodedSuccess)
        let decodedFailure = try JamDecoder.decode(MyResult<String>.self, from: encodedFailure)
        #expect(decodedFailure != nil)
        #expect(decodedSuccess != nil)
    }

    @Test func variant() throws {
        let successResult: Result<String, ResultError> = .success("Success!")
        let failureResult: Result<String, Int> = .failure(0)
        let encodedSuccess = try JamEncoder.encode(successResult)
        let encodedFailure = try JamEncoder.encode(failureResult)
        let invalidData0 = Data([0x00] + encodedSuccess)
        let invalidData1 = Data([0x01] + encodedFailure)
        // Invalid variant value (e.g. value 2)
        let invalidData = Data([0x02] + "Invalid variant".utf8)
        let decoded0 = try JamDecoder.decode(Result<String, ResultError>.self, from: invalidData0)
        let decoded1 = try JamDecoder.decode(Result<String, Int>.self, from: invalidData1)
        #expect(decoded0 != nil)
        #expect(decoded1 != nil)
        // Expect decoding to fail and return nil
        #expect(throws: Error.self) {
            _ = try JamDecoder.decode(Result<String, ResultError>.self, from: invalidData)
        }
    }
}
