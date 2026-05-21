@testable import Blockchain
import Foundation
import Testing

struct TimeProviderTests {
    @Test func jamCommonEraDateOffset() {
        let beginning = Date(timeIntervalSince1970: Double(Date.jamCommonEraBeginning))
        let oneMinuteLater = Date(timeIntervalSince1970: Double(Date.jamCommonEraBeginning + 60))

        #expect(beginning.timeIntervalSinceJamCommonEra == 0)
        #expect(oneMinuteLater.timeIntervalSinceJamCommonEra == 60)
    }

    @Test func mockTimeProviderAdvancesAndTruncatesToJamTime() {
        let provider = MockTimeProvider(time: 10.75)

        #expect(provider.getTimeInterval() == 10.75)
        #expect(provider.getTime() == 10)

        provider.advance(by: 4.5)
        #expect(provider.getTimeInterval() == 15.25)

        provider.advance(to: 3.5)
        #expect(provider.getTimeInterval() == 3.5)
        #expect(provider.getTime() == 3)
    }
}
