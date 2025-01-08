import Foundation
import Testing
import Utils

@testable import Blockchain

struct LogTests {
    @Test func testLogDetailJSON() async throws {
        let logDetials = Log.Details(
            time: "2023-04-01 12:00:00",
            level: .error,
            target: Data("target".utf8),
            message: Data("message".utf8),
            core: nil,
            service: 1
        )
        let json = logDetials.json
        #expect(json["time"]?.string == "2023-04-01 12:00:00")
        #expect(json["level"]?.string == "ERROR")
        #expect(json["target"]?.string == "target")
        #expect(json["message"]?.string == "message")
        #expect(json["service"]?.string == "1")
        #expect(json["core"] == .null)
    }

    @Test func testLogDetailString() async throws {
        let logDetials = Log.Details(
            time: "2023-04-01 12:00:00",
            level: .trace,
            target: Data("target".utf8),
            message: Data("message".utf8),
            core: nil,
            service: nil
        )
        let str = logDetials.str
        #expect(str == "2023-04-01 12:00:00 TRACE target message")
    }

    @Test func testLogDetailInvalidString() async throws {
        let invalidData = Data([0xFF, 0xFE, 0xFD])
        let logDetails = Log.Details(
            time: "2023-04-01 12:00:00",
            level: .warn,
            target: invalidData,
            message: invalidData,
            core: nil,
            service: nil
        )
        let str = logDetails.str
        #expect(str == "2023-04-01 12:00:00 WARN invalid string invalid string")
    }
}
