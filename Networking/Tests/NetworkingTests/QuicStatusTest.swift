import Testing

@testable import Networking

struct QuicStatusTests {
    @Test func unknownStatus() throws {
        #expect(QuicStatusCode.unknown == QuicStatusCode.from(rawValue: 888))
    }

    @Test func successStatus() throws {
        #expect(QuicStatusCode.success == QuicStatusCode.from(rawValue: 0))
        #expect(QuicStatusCode.from(rawValue: 0).rawValue.isSucceeded)
    }

    @Test func failureStatus() throws {
        let status: QuicStatus = 2
        #expect(QuicStatusCode.notFound == QuicStatusCode.from(rawValue: status))
        #expect(status.isFailed)
    }

    @Test func isFailed() throws {
        #expect(QuicStatusCode.notFound.rawValue.isFailed)
        #expect(!QuicStatusCode.success.rawValue.isFailed)
    }
}
