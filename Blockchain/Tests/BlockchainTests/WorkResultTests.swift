@testable import Blockchain
import Codec
import Foundation
import Testing

struct WorkResultTests {
    @Test
    func jamCodecRoundTripsSuccessAndFailureVariants() throws {
        try assertJamRoundTrip(WorkResult(.success(Data([1, 2, 3]))), expectedEncodedSize: 5)

        for error in WorkResultError.allCases {
            try assertJamRoundTrip(WorkResult(.failure(error)), expectedEncodedSize: 1)
        }
    }

    @Test
    func jsonCodecRoundTripsSuccessAndFailureVariants() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let success = WorkResult(.success(Data([4, 5, 6])))
        let decodedSuccess = try decoder.decode(WorkResult.self, from: encoder.encode(success))
        #expect(decodedSuccess.result.successValue == Data([4, 5, 6]))

        for error in WorkResultError.allCases {
            let decoded = try decoder.decode(WorkResult.self, from: encoder.encode(WorkResult(.failure(error))))
            #expect(sameWorkResultError(decoded.result.failureValue, error))
        }
    }

    @Test
    func jamCodecRejectsUnknownVariant() throws {
        #expect(throws: DecodingError.self) {
            _ = try JamDecoder.decode(WorkResult.self, from: Data([7]))
        }
    }

    private func assertJamRoundTrip(
        _ value: WorkResult,
        expectedEncodedSize: Int,
    ) throws {
        let encoded = try JamEncoder.encode(value)
        let decoded = try JamDecoder.decode(WorkResult.self, from: encoded)

        #expect(decoded.result.successValue == value.result.successValue)
        #expect(sameWorkResultError(decoded.result.failureValue, value.result.failureValue))
        #expect(value.encodedSize == expectedEncodedSize)
        #expect(WorkResult.encodeedSizeHint == nil)
    }

    private func sameWorkResultError(_ lhs: WorkResultError?, _ rhs: WorkResultError?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil),
             (.outOfGas?, .outOfGas?),
             (.panic?, .panic?),
             (.badExports?, .badExports?),
             (.overSize?, .overSize?),
             (.invalidCode?, .invalidCode?),
             (.codeTooLarge?, .codeTooLarge?):
            true
        default:
            false
        }
    }
}

extension Result where Failure == WorkResultError {
    fileprivate var successValue: Success? {
        try? get()
    }

    fileprivate var failureValue: WorkResultError? {
        if case let .failure(error) = self {
            error
        } else {
            nil
        }
    }
}
